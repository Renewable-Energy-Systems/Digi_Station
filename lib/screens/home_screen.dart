// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_constants.dart';

// Helper: parse DET -> ParameterNo (keeps compatibility with det_selector)
int? detToParamNumber(String detName) {
  final re = RegExp(r'det\s*0*(\d+)', caseSensitive: false);
  final m = re.firstMatch(detName);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

// Fetch master info from server by parameter number (keeps existing behaviour)
Future<Map<String, dynamic>?> fetchSensorInfoFromServerByParam(
  String apiHost,
  int param,
) async {
  try {
    final uri = Uri.parse(
      '$apiHost/api/sensorinfo',
    ).replace(queryParameters: {'param': param.toString()});
    final resp = await http.get(uri).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    print('[DEBUG] sensorinfo response: ${resp.body}'); // Added debug log
    final j = json.decode(resp.body);
    if (j is Map && j['found'] == true && j['sensor'] is Map) {
      return Map<String, dynamic>.from(j['sensor']);
    }
  } catch (e) {
    print('fetchSensorInfoFromServerByParam error: $e');
  }
  return null;
}

// Load local override saved on tablet
Future<Map<String, String>?> loadLocalSensorInfo(int param) async {
  final prefs = await SharedPreferences.getInstance();
  final k = 'sensor_local_$param';
  final s = prefs.getString(k);
  if (s == null) return null;
  final j = json.decode(s) as Map<String, dynamic>;
  return j.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}

// Utility: get effective info (local override preferred)
Future<Map<String, String>> getEffectiveSensorInfo(
  String detName,
  String apiHost,
) async {
  final param = detToParamNumber(detName);
  if (param == null) {
    return {
      'workstation': '',
      'probeId': '',
      'calibrationDate': '',
      'calibrationDue': '',
      'min': '',
      'max': '',
    };
  }

  final local = await loadLocalSensorInfo(param);
  if (local != null) return local;

  final master = await fetchSensorInfoFromServerByParam(apiHost, param);
  if (master != null) {
    String stripDate(dynamic v) {
      if (v == null) return '';
      final s = v.toString();
      final idx = s.indexOf('T');
      return idx > 0 ? s.substring(0, idx) : s;
    }

    return {
      'workstation': master['ChannelName']?.toString() ?? '',
      'probeId': master['SenID']?.toString() ?? '',
      'calibrationDate': stripDate(master['Cali.Date']),
      'calibrationDue': stripDate(master['Cali.Due']),
      'min': master['Min']?.toString() ?? '',
      'max': master['Max']?.toString() ?? '',
    };
    print('[DEBUG] Parsed info: $master'); // Added debug log
    return {
      'workstation': master['ChannelName']?.toString() ?? '',
      'probeId': master['SenID']?.toString() ?? '',
      'calibrationDate': stripDate(master['Cali.Date']),
      'calibrationDue': stripDate(master['Cali.Due']),
      'min': master['Min']?.toString() ?? '',
      'max': master['Max']?.toString() ?? '',
    };
  }

  return {
    'workstation': '',
    'probeId': '',
    'calibrationDate': '',
    'calibrationDue': '',
    'min': '',
    'max': '',
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  // Colors (same as your original)
  static const blueMain = Color(0xFF0A66FF); // header + bottom bar
  static const bgGradientTop = Color(0xFFF7FAFF); // page bg start
  static const bgGradientBottom = Color(0xFFF2F6FF); // page bg end
  static const cardBorder = Color(0xFFE6ECFF);
  static const panelBorder = Color(0xFFE1E8FF);
  static const headingText = Color(0xFF1C3366); // "Sensor Information" etc.
  static const labelText = Color(0xFF5A6B8A); // labels in left card
  static const valueText = Color(0xFF103B8C); // values in left card
  static const captionText = Color(0xFF7A8AA6); // "Updated: ..."

  // API host & websocket url
  final String apiHost = ApiConstants.detApiHost;
  final String wsUrl = ApiConstants.detWsUrl;

  // Sensor info displayed in left card (can be changed locally on tablet)
  String workstationName = '';
  String probeId = '';
  String calibrationDate = '';
  String calibrationDue = '';
  String minVal = '';
  String maxVal = '';

  // Dew point display & last-updated timestamp (moved to dew card)
  String dewPointDisplay = '-- °C';
  String ppmDisplay = '-- ppm'; // Added state for PPM
  String updatedAt = '––';
  String status = 'idle';

  // Helper: Calculate Corrected Sonntag (ppmv)
  String calculateSonntagPpm(double tempC) {
    const double P = 101325.0; // Standard atmospheric pressure in Pa
    final double T = tempC + 273.15; // Kelvin

    double lnEs;
    if (tempC < 0.01) {
      // Over ice (Sonntag 1990)
      lnEs =
          -6024.5282 / T +
          29.32707 +
          1.0613868e-2 * T -
          1.3198825e-5 * T * T -
          0.49382577 * math.log(T);
    } else {
      // Over water
      lnEs =
          -6096.9385 / T +
          21.2409642 -
          2.711193e-2 * T +
          1.673952e-5 * T * T +
          2.433502 * math.log(T);
    }

    final double es = math.exp(lnEs); // Vapor pressure in Pa
    final double ppm = (es / (P - es)) * 1e6;

    // Format: integer for most, maybe 1 decimal if small?
    // User table shows integers even for small values (e.g. 5).
    // Let's stick to integer for consistency with table, unless < 1.
    if (ppm < 1.0 && ppm > 0.0) {
      return '${ppm.toStringAsFixed(2)} ppm';
    }
    return '${ppm.round()} ppm';
  }

  // DET column currently selected (from shared prefs)
  String selectedDetColumn = 'Det01 (°C)';

  // WebSocket channel & subscription tracking
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  String? _subscribedCol; // currently subscribed column on WS

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _loadSelectedDetAndSensorInfo();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    super.dispose();
  }

  Future<void> _loadSelectedDetAndSensorInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDet = prefs.getString('selected_det_column');
    if (savedDet != null) selectedDetColumn = savedDet;

    // load effective sensor info
    final info = await getEffectiveSensorInfo(selectedDetColumn, apiHost);
    if (mounted) {
      setState(() {
        workstationName = info['workstation'] ?? '';
        probeId = info['probeId'] ?? '';
        calibrationDate = info['calibrationDate'] ?? '';
        calibrationDue = info['calibrationDue'] ?? '';
        minVal = info['min'] ?? '';
        maxVal = info['max'] ?? '';

        // don't change dewpoint on load; updatedAt will be set when WS message arrives
      });
    }

    // ensure WS subscription matches selected DET
    _subscribeToColumn(selectedDetColumn);
  }

  // (re)connect WebSocket channel used to receive dewpoint updates
  void _connectWebSocket() {
    // close previous
    _wsSub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    try {
      _channel = IOWebSocketChannel.connect(wsUrl);
      _wsSub = _channel!.stream.listen(
        (message) {
          _handleWsMessage(message);
        },
        onError: (err) {
          print('[WS] error: $err');
          // keep status updated
          if (mounted) setState(() => status = 'ws-err');
        },
        onDone: () {
          print('[WS] closed');
          if (mounted) setState(() => status = 'ws-closed');
          // try reconnect after a short delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _connectWebSocket();
          });
        },
        cancelOnError: true,
      );
      if (mounted) setState(() => status = 'ws-connected');
      // subscribe if we already know selected column
      if (selectedDetColumn.isNotEmpty) _subscribeToColumn(selectedDetColumn);
    } catch (e) {
      print('[WS] connect exception: $e');
      if (mounted) setState(() => status = 'ws-failed');
      // schedule retry
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _connectWebSocket();
      });
    }
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final m = json.decode(raw.toString());
      if (m is Map && m['type'] == 'update') {
        final col = m['col']?.toString();
        // Only accept updates for currently selected column (robust)
        if (col != null && col == selectedDetColumn) {
          final dew = m['dewpoint_c'];
          final date = m['date'] ?? '';
          final time = m['time'] ?? '';
          String dewStr;
          if (dew == null ||
              dew.toString().toLowerCase() == 'null' ||
              dew.toString().trim() == '') {
            dewStr = '-- °C';
          } else {
            // dew may already be a string with 2 decimals; ensure formatted
            dewStr = '${dew.toString()} °C';
          }
          final updated = (date != '' || time != '')
              ? '$date $time'
              : DateTime.now().toString();

          if (mounted) {
            setState(() {
              dewPointDisplay = dewStr;
              // Calculate PPM if we have a valid dew point
              if (dew != null &&
                  dew.toString().toLowerCase() != 'null' &&
                  dew.toString().trim() != '') {
                final double? val = double.tryParse(dew.toString());
                if (val != null) {
                  ppmDisplay = calculateSonntagPpm(val);
                } else {
                  ppmDisplay = '-- ppm';
                }
              } else {
                ppmDisplay = '-- ppm';
              }
              updatedAt = updated;
              status = 'ok';
            });
          }
        }
      } else if (m is Map && m['type'] == 'columns') {
        // ignore for now
      } else if (m is Map && m['type'] == 'subscribed') {
        print('[WS] subscribed: ${m['col']}');
      }
    } catch (e) {
      print('[WS] message parse error: $e -- raw: $raw');
    }
  }

  // subscribe/unsubscribe helpers (sends JSON action messages to WS)
  void _subscribeToColumn(String col) {
    // if channel not ready, we'll attempt again after small delay (connect may be async)
    if (_channel == null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _subscribeToColumn(col);
      });
      return;
    }

    try {
      // if previously subscribed to a different column, unsubscribe it first
      if (_subscribedCol != null && _subscribedCol != col) {
        final msg = json.encode({
          'action': 'unsubscribe',
          'col': _subscribedCol,
        });
        _channel!.sink.add(msg);
      }

      // send subscribe for the requested column
      final subMsg = json.encode({'action': 'subscribe', 'col': col});
      _channel!.sink.add(subMsg);
      _subscribedCol = col;
      print('[WS] subscribe sent for $col');
    } catch (e) {
      print('[WS] subscribe error: $e');
    }
  }

  // manual refresh (if you call it)
  Future<void> refreshSensorInfo() async {
    // RELOAD the selected DET from prefs so we pick up the change
    final prefs = await SharedPreferences.getInstance();
    final savedDet = prefs.getString('selected_det_column');
    if (savedDet != null) {
      setState(() => selectedDetColumn = savedDet);
    }

    final info = await getEffectiveSensorInfo(selectedDetColumn, apiHost);
    if (mounted) {
      setState(() {
        workstationName = info['workstation'] ?? '';
        probeId = info['probeId'] ?? '';
        calibrationDate = info['calibrationDate'] ?? '';
        calibrationDue = info['calibrationDue'] ?? '';
        minVal = info['min'] ?? '';
        maxVal = info['max'] ?? '';

        updatedAt = DateTime.now().toString();
      });
    }
    // re-subscribe to ensure WS streaming
    _subscribeToColumn(selectedDetColumn);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgGradientTop, bgGradientBottom],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // ===== Top App Bar =====
              const _TopHeader(blueMain: blueMain),

              const SizedBox(height: 16),

              // ===== Main White Panel with 2 cards inside =====
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: panelBorder, width: 2),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 780;

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SensorCard(
                              headingText: headingText,
                              labelText: labelText,
                              valueText: valueText,
                              captionText: captionText,
                              cardBorder: cardBorder,
                              workstationName: workstationName,
                              probeId: probeId,
                              calibrationDate: calibrationDate,
                              calibrationDue: calibrationDue,
                            ),
                            const SizedBox(height: 24),
                            _DewPointCard(
                              dewBg: const Color(0xFFF4F8FF),
                              dewBorder: const Color(0xFFDFE8FF),
                              dewLabelText: const Color(0xFF1C3FAA),
                              dewBigNumber: const Color(0xFF0A66FF),
                              updatedAt: updatedAt,
                              dewPointDisplay: dewPointDisplay,
                              ppmDisplay: ppmDisplay,
                              minVal: minVal,
                              maxVal: maxVal,
                            ),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            flex: 4,
                            child: _SensorCard(
                              headingText: headingText,
                              labelText: labelText,
                              valueText: valueText,
                              captionText: captionText,
                              cardBorder: cardBorder,
                              workstationName: workstationName,
                              probeId: probeId,
                              calibrationDate: calibrationDate,
                              calibrationDue: calibrationDue,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Flexible(
                            flex: 4,
                            child: _DewPointCard(
                              dewBg: const Color(0xFFF4F8FF),
                              dewBorder: const Color(0xFFDFE8FF),
                              dewLabelText: const Color(0xFF1C3FAA),
                              dewBigNumber: const Color(0xFF0A66FF),
                              updatedAt: updatedAt,
                              dewPointDisplay: dewPointDisplay,
                              ppmDisplay: ppmDisplay,
                              minVal: minVal,
                              maxVal: maxVal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ===== Bottom blue strip =====
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: blueMain,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------- Reused widgets (unchanged except where requested) ----------------------

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.blueMain});

  final Color blueMain;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: blueMain,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1B2B65),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            height: 56,
            width: 80,
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Image.asset('assets/res_logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Renewable Energy Systems Limited',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 72),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.headingText,
    required this.labelText,
    required this.valueText,
    required this.captionText,
    required this.cardBorder,
    required this.workstationName,
    required this.probeId,
    required this.calibrationDate,
    required this.calibrationDue,
  });

  final Color headingText;
  final Color labelText;
  final Color valueText;
  final Color captionText;
  final Color cardBorder;

  final String workstationName;
  final String probeId;
  final String calibrationDate;
  final String calibrationDue;

  TextStyle get _headingStyle =>
      TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: headingText);

  TextStyle get _labelStyle => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: labelText,
  );

  TextStyle get _valueStyle => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.3,
    color: valueText,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 320,
        maxWidth: 480,
        minHeight: 200,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(31, 27, 43, 101),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sensor Information', style: _headingStyle),
          const SizedBox(height: 24),
          _twoColRow('Workstation name:', workstationName),
          const SizedBox(height: 16),
          _twoColRow('Probe ID:', probeId),
          const SizedBox(height: 16),
          _twoColRow('Calibration Date:', calibrationDate),
          const SizedBox(height: 16),
          _twoColRow('Calibration Due:', calibrationDue),
          const SizedBox(height: 24),
          const Spacer(),
          // NOTE: Removed Updated: from this card (user requested)
        ],
      ),
    );
  }

  Widget _twoColRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label, style: _labelStyle)),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: Text(value, style: _valueStyle)),
      ],
    );
  }
}

class _DewPointCard extends StatelessWidget {
  const _DewPointCard({
    required this.dewBg,
    required this.dewBorder,
    required this.dewLabelText,
    required this.dewBigNumber,
    required this.dewPointDisplay,
    required this.ppmDisplay,
    required this.updatedAt,
    required this.minVal,
    required this.maxVal,
  });

  final Color dewBg;
  final Color dewBorder;
  final Color dewLabelText;
  final Color dewBigNumber;

  final String dewPointDisplay;
  final String ppmDisplay;
  final String updatedAt;
  final String minVal;
  final String maxVal;

  TextStyle get _headingStyle =>
      TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: dewLabelText);

  Color get _statusColor {
    // Clean string to get number
    final cleanVal = dewPointDisplay.replaceAll(RegExp(r'[^0-9.-]'), '');
    final val = double.tryParse(cleanVal);
    final min = double.tryParse(minVal);
    final max = double.tryParse(maxVal);

    if (val != null && min != null && max != null) {
      if (val >= min && val <= max) {
        return const Color(0xFF00C853); // Green for In Range (OK)
      } else {
        return const Color(0xFFD50000); // Red for Out of Range
      }
    }
    return dewBigNumber; // Default Blue if range not defined
  }

  TextStyle get _bigNumberStyle => TextStyle(
    fontSize: 96, // Slightly reduced to fit both
    fontWeight: FontWeight.w900,
    height: 1.0,
    color: _statusColor, // Dynamic color
    letterSpacing: -2,
  );

  TextStyle get _ppmLabelStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: dewLabelText.withOpacity(0.7),
    letterSpacing: 0.5,
  );

  TextStyle get _ppmValueStyle =>
      TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: dewLabelText);

  TextStyle get _updatedStyle => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFF7A8AA6),
  );

  TextStyle get _minMaxLabelStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: dewLabelText.withOpacity(0.6),
  );

  TextStyle get _minMaxValueStyle => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: dewBigNumber, // Use the blue color for values
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 300,
        maxWidth: 480,
        minHeight: 200,
      ),
      padding: const EdgeInsets.all(20), // Slightly reduced padding
      decoration: BoxDecoration(
        color: dewBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dewBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(41, 27, 43, 101),
            offset: Offset(0, 8),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A8DFF).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.opacity_rounded,
                  size: 20,
                  color: Color(0xFF5A8DFF),
                ),
              ),
              const SizedBox(width: 8),
              Text('Dew Point / PPMv', style: _headingStyle),

              const Spacer(),

              // LIVE Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9), // Light green bg
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4CAF50), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32), // Darker green dot
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // Main values Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dew Point Section
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fixed height container to align baselines and labels
                    SizedBox(
                      height: 60,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            dewPointDisplay,
                            style: _bigNumberStyle.copyWith(
                              fontSize: 42,
                            ), // Reduced to proper fit
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("Dew Point", style: _ppmLabelStyle),
                  ],
                ),
              ),

              // Vertical Divider
              Container(
                height: 50,
                width: 2,
                color: const Color(0xFFE2E8F0),
                margin: const EdgeInsets.symmetric(horizontal: 24),
              ),

              // PPM Section
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 60,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            ppmDisplay.replaceAll(' ppm', ''),
                            style: _bigNumberStyle.copyWith(
                              fontSize: 42,
                              color: _statusColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("PPMv", style: _ppmLabelStyle),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          if (true) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12.0),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // Subtle grey background
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Text(
                    "PERMITTED RANGE",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: dewLabelText.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMinMax("Min", minVal),
                      Container(
                        width: 1,
                        height: 24,
                        color: const Color(0xFFCBD5E1),
                      ), // Vertical divider
                      _buildMinMax("Max", maxVal),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Updated timestamp
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Updated: $updatedAt', style: _updatedStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildMinMax(String label, String val) {
    final displayVal = val.isEmpty ? '--' : '$val °C';
    // Check if value is actually empty or null to decide on styling
    // But here we rely on text. Using a larger font for visibility.
    return Column(
      children: [
        Text(
          displayVal,
          style: TextStyle(
            fontSize: 24, // Much larger for visibility from distance
            fontWeight: FontWeight.w800,
            color: dewBigNumber,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: dewLabelText.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}
