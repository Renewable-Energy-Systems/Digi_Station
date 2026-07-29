// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_constants.dart';
import '../utils/dew_point_converter.dart';
import '../socket_service.dart';
import '../models/process_slip_model.dart';
import '../services/process_slip_service.dart';
import '../services/config_service.dart';
import '../services/voice_alert_service.dart';

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
    if (resp.statusCode == 200) {
      debugPrint('[DEBUG] sensorinfo response: ${resp.body}'); // Added debug log
      final j = json.decode(resp.body);
      if (j is Map && j['found'] == true && j['sensor'] is Map) {
        final sensorData = Map<String, dynamic>.from(j['sensor']);
        // Cache successful response
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'sensor_master_cache_$param',
          json.encode(sensorData),
        );
        return sensorData;
      }
    }
  } catch (e) {
    debugPrint('fetchSensorInfoFromServerByParam error: $e');
  }

  // Fallback to cache if network request fails
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('sensor_master_cache_$param');
    if (cached != null) {
      debugPrint('[DEBUG] using cached sensorinfo for param $param');
      return Map<String, dynamic>.from(json.decode(cached));
    }
  } catch (e) {
    debugPrint('fetchSensorInfoFromServerByParam cache error: $e');
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
  final VoidCallback? onNavigateToSensorConfig;

  const HomeScreen({super.key, this.onNavigateToSensorConfig});

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

  // DET column currently selected (from shared prefs)
  String selectedDetColumn = 'Det01 (C)';

  // Whether a sensor/DET has been explicitly configured for this station.
  // Until then the home screen shows a "Configure sensor" guide instead of
  // placeholder Probe ID / permitted-range values.
  bool _sensorConfigured = false;

  // Spoken dew-point out-of-range alerts (female TTS voice).
  final VoiceAlertService _voiceAlert = VoiceAlertService();
  bool _dewOutOfRangeActive = false;
  DateTime? _lastDewVoiceAlert;
  static const Duration _dewVoiceInterval = Duration(seconds: 15);

  // Process Slip State
  ProcessSlip? _currentSlip;
  bool _isSlipVisible = false;
  bool _isFetchingSlip = false;
  bool _showAllRows = false;
  final ProcessSlipService _slipService = ProcessSlipService();
  DateTime? _slipFetchDate; // date when current slip was fetched
  Timer? _midnightTimer; // timer to clear slip at midnight

  // Subscription tracking
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;
  SocketConnectionState _connState = SocketConnectionState.disconnected;

  http.Client? _sseClient;

  @override
  void initState() {
    super.initState();
    _voiceAlert.init();
    _initAll();
  }

  Future<void> _initAll() async {
    await _loadSelectedDetAndSensorInfo();
    _listenToSocket();
    // Only fetch/stream process slips when this station uses the ops API —
    // otherwise it never contacts the ops server (no slip card, no errors).
    if (await ConfigService().isStationApiEnabled()) {
      _refreshSlip();
      _listenToSlipUpdates();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    _sseClient?.close();
    _midnightTimer?.cancel();
    _voiceAlert.stop();
    super.dispose();
  }

  bool _logoPrecached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoPrecached) {
      _logoPrecached = true;
      // Decode the header logo ahead of first paint to avoid a flash-in.
      precacheImage(const AssetImage('assets/res_logo.png'), context);
    }
  }

  Future<void> _loadSelectedDetAndSensorInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDet = prefs.getString('selected_det_column');
    if (savedDet != null) selectedDetColumn = savedDet;

    // load effective sensor info
    final info = await getEffectiveSensorInfo(selectedDetColumn, apiHost);
    if (mounted) {
      setState(() {
        _sensorConfigured = savedDet != null;
        workstationName = info['workstation'] ?? '';
        probeId = info['probeId'] ?? '';
        calibrationDate = info['calibrationDate'] ?? '';
        calibrationDue = info['calibrationDue'] ?? '';
        minVal = info['min'] ?? '';
        maxVal = info['max'] ?? '';
        // Clear old dewpoint data when loading new DET
        dewPointDisplay = '-- °C';
        ppmDisplay = '-- ppm';
        updatedAt = '––';
      });
    }

    // ensure WS subscription matches selected DET
    SocketService().subscribeDewpoint(selectedDetColumn);
  }

  // Listen to centralized WebSocket service
  void _listenToSocket() {
    _msgSub?.cancel();
    _statusSub?.cancel();

    final ss = SocketService();

    // Initial state
    _connState = ss.wsState;

    _msgSub = ss.dewpointStream.listen((m) {
      _handleWsMessage(m);
    });

    _statusSub = ss.wsStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _connState = state;
          if (state == SocketConnectionState.connected) {
            status = 'ok';
          } else {
            status = 'offline';
          }
        });
      }
    });

    // If already connected, ensure we are subscribed
    if (ss.wsState == SocketConnectionState.connected) {
      ss.subscribeDewpoint(selectedDetColumn);
    }
  }

  void _handleWsMessage(dynamic msg) {
    try {
      if (msg is! Map) return;
      final m = msg;
      if (m['type'] == 'update') {
        final col = m['col']?.toString();
        // Only accept updates for currently selected column (robust)
        if (col != null && col == selectedDetColumn) {
          final dew = m['dewpoint_c'];

          if (dew != null &&
              dew.toString().toLowerCase() != 'null' &&
              dew.toString().trim() != '') {
            final double? dewVal = double.tryParse(dew.toString());
            if (dewVal == 0.0) {
              return; // Ignore exact zero values
            }
          }

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
                  // Use lookup table converter
                  ppmDisplay = DewPointConverter.getPpmString(val);
                } else {
                  ppmDisplay = '-- ppm';
                }
              } else {
                ppmDisplay = '-- ppm';
              }
              updatedAt = updated;
              status = 'ok';
            });
            _checkDewPointAlert();
          }
        }
      } else if (m['type'] == 'columns') {
        // ignore for now
      } else if (m['type'] == 'subscribed') {
        debugPrint('[WS] subscribed: ${m['col']}');
      }
    } catch (e) {
      debugPrint('[WS] message processing error: $e -- data: $msg');
    }
  }

  /// Speaks a warning (debounced) whenever the live dew point is outside the
  /// permitted [minVal, maxVal] range. Re-entering the range re-arms it so the
  /// next excursion alerts immediately.
  void _checkDewPointAlert() {
    final val = double.tryParse(
      dewPointDisplay.replaceAll(RegExp(r'[^0-9.-]'), ''),
    );
    final min = double.tryParse(minVal);
    final max = double.tryParse(maxVal);

    // Need a live reading and a configured range to judge.
    if (val == null || min == null || max == null) {
      _dewOutOfRangeActive = false;
      return;
    }

    final outOfRange = val < min || val > max;
    if (!outOfRange) {
      _dewOutOfRangeActive = false;
      return;
    }

    final now = DateTime.now();
    final due =
        _lastDewVoiceAlert == null ||
        now.difference(_lastDewVoiceAlert!) > _dewVoiceInterval;
    if (!_dewOutOfRangeActive || due) {
      _dewOutOfRangeActive = true;
      _lastDewVoiceAlert = now;
      _voiceAlert.speakDewPointOutOfRange();
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
        _sensorConfigured = savedDet != null;
        workstationName = info['workstation'] ?? '';
        probeId = info['probeId'] ?? '';
        calibrationDate = info['calibrationDate'] ?? '';
        calibrationDue = info['calibrationDue'] ?? '';
        minVal = info['min'] ?? '';
        maxVal = info['max'] ?? '';

        // Reset display while waiting for new data
        dewPointDisplay = '-- °C';
        ppmDisplay = '-- ppm';
        updatedAt = '––';
      });
    }
    // re-subscribe to ensure WS streaming
    SocketService().subscribeDewpoint(selectedDetColumn);
    _refreshSlip();
  }

  // SSE Listener for Instant Process Slip Updates
  Future<void> _listenToSlipUpdates() async {
    final baseUrl = await ConfigService().getOpsDigiBaseUrl();
    final url = Uri.parse('$baseUrl/api_slip_stream.php');

    _sseClient?.close();
    _sseClient = http.Client();
    try {
      final request = http.Request('GET', url);
      final response = await _sseClient!.send(request);

      response.stream
          .transform(utf8.decoder)
          .listen(
            (data) {
              if (data.contains('slip_updated')) {
                _refreshSlip(showErrors: false);
              }
            },
            onDone: () {
              // Reconnect when the server closes the connection (every 5 minutes)
              if (mounted) {
                Future.delayed(
                  const Duration(seconds: 2),
                  _listenToSlipUpdates,
                );
              }
            },
            onError: (e) {
              if (mounted) {
                Future.delayed(
                  const Duration(seconds: 5),
                  _listenToSlipUpdates,
                );
              }
            },
          );
    } catch (e) {
      if (mounted) {
        Future.delayed(const Duration(seconds: 5), _listenToSlipUpdates);
      }
    }
  }

  Future<void> _refreshSlip({bool showErrors = true}) async {
    if (_isFetchingSlip) return;

    final workstationId = await ConfigService().getWorkstationId();
    if (workstationId == null || workstationId.isEmpty) return;

    if (mounted) setState(() => _isFetchingSlip = true);

    try {
      final slip = await _slipService.fetchLatestSlip(workstationId);
      if (mounted) {
        setState(() {
          _currentSlip = slip;
          _slipFetchDate = DateTime.now();
          _isFetchingSlip = false;
        });
        _scheduleMidnightCheck();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingSlip = false);
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Slip Error: $e'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  /// Check if the current slip is expired (fetched on a previous day)
  bool get _isSlipExpired {
    if (_slipFetchDate == null || _currentSlip == null) return false;
    final now = DateTime.now();
    return now.year != _slipFetchDate!.year ||
        now.month != _slipFetchDate!.month ||
        now.day != _slipFetchDate!.day;
  }

  /// Schedule a timer that fires at midnight to expire the current slip
  void _scheduleMidnightCheck() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final duration = midnight.difference(now);
    _midnightTimer = Timer(duration, () {
      if (mounted) {
        setState(() {}); // rebuild to show "No Production"
        // Try fetching a new slip for the new day
        _refreshSlip(showErrors: false);
        // Schedule again for the next midnight
        _scheduleMidnightCheck();
      }
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Container(
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
                                  configured: _sensorConfigured,
                                  onConfigure: widget.onNavigateToSensorConfig,
                                  workstationName: workstationName,
                                  probeId: probeId,
                                  calibrationDate: calibrationDate,
                                  calibrationDue: calibrationDue,
                                  slip: _currentSlip,
                                  isSlipExpired: _isSlipExpired,
                                  onSlipTap: (_currentSlip != null && !_isSlipExpired)
                                      ? () => setState(
                                          () => _isSlipVisible = true,
                                        )
                                      : null,
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
                                  showRange: _sensorConfigured,
                                  isLive:
                                      (_connState ==
                                          SocketConnectionState.connected &&
                                      dewPointDisplay != '-- °C'),
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
                                  configured: _sensorConfigured,
                                  onConfigure: widget.onNavigateToSensorConfig,
                                  workstationName: workstationName,
                                  probeId: probeId,
                                  calibrationDate: calibrationDate,
                                  calibrationDue: calibrationDue,
                                  slip: _currentSlip,
                                  isSlipExpired: _isSlipExpired,
                                  onSlipTap: (_currentSlip != null && !_isSlipExpired)
                                      ? () => setState(
                                          () => _isSlipVisible = true,
                                        )
                                      : null,
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
                                  showRange: _sensorConfigured,
                                  isLive:
                                      (_connState ==
                                          SocketConnectionState.connected &&
                                      dewPointDisplay != '-- °C'),
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
        ),

        // --- Process Slip Overlay ---
        if (_isSlipVisible)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _isSlipVisible = false),
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),

        // --- Centered Slip Content ---
        if (_currentSlip != null && _isSlipVisible)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _ProcessSlipContent(
                slip: _currentSlip!,
                workstationName: workstationName,
                showAll: _showAllRows,
                onToggleShowAll: () =>
                    setState(() => _showAllRows = !_showAllRows),
                onClose: () => setState(() => _isSlipVisible = false),
              ),
            ),
          ),

        // (Process Slip info is now inline in the Sensor Card)
      ],
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
    this.configured = true,
    this.onConfigure,
    this.slip,
    this.isSlipExpired = false,
    this.onSlipTap,
  });

  final Color headingText;
  final Color labelText;
  final Color valueText;
  final Color captionText;
  final Color cardBorder;

  final bool configured;
  final VoidCallback? onConfigure;

  final String workstationName;
  final String probeId;
  final String calibrationDate;
  final String calibrationDue;
  final ProcessSlip? slip;
  final bool isSlipExpired;
  final VoidCallback? onSlipTap;

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
    final calibAlert = configured ? _buildCalibrationAlert() : null;
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
          if (!configured)
            Expanded(child: Center(child: _buildConfigureGuide()))
          else ...[
            _twoColRow('Workstation name:', workstationName),
            const SizedBox(height: 16),
            _twoColRow('Probe ID:', probeId),
            const SizedBox(height: 16),
            _twoColRow('Calibration Date:', calibrationDate),
            const SizedBox(height: 16),
            _twoColRow('Calibration Due:', calibrationDue),
            if (calibAlert != null) ...[
              const SizedBox(height: 14),
              calibAlert,
            ],
            const Spacer(),
            // Current Process Details inline card (only when workstation is selected)
            if (slip != null && !isSlipExpired) _buildSlipCard(),
            if (isSlipExpired) _buildNoProductionCard(),
          ],
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

  // Show a warning this many days before the calibration due date.
  static const int _calibWarnWindowDays = 30;

  /// A badge warning that the sensor calibration is overdue or coming up,
  /// derived from [calibrationDue]. Returns null when it's still in date /
  /// unavailable.
  Widget? _buildCalibrationAlert() {
    final due = _parseDate(calibrationDue);
    if (due == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final daysLeft = dueDay.difference(today).inDays;

    if (daysLeft < 0) {
      final ago = -daysLeft;
      return _calibBadge(
        Icons.error_rounded,
        const Color(0xFFD50000),
        'CALIBRATION OVERDUE',
        ago == 1 ? 'Due 1 day ago' : 'Due $ago days ago',
      );
    }
    if (daysLeft <= _calibWarnWindowDays) {
      return _calibBadge(
        Icons.warning_amber_rounded,
        const Color(0xFFF57C00),
        daysLeft == 0 ? 'CALIBRATION DUE TODAY' : 'CALIBRATION DUE SOON',
        daysLeft == 0
            ? 'Due today'
            : (daysLeft == 1 ? 'Due in 1 day' : 'Due in $daysLeft days'),
      );
    }
    return null; // in date
  }

  Widget _calibBadge(IconData icon, Color color, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.4,
                    color: color,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parse a 'YYYY-MM-DD' (optionally with a time suffix) date; null if it
  /// can't be understood.
  DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final d = int.tryParse(m.group(3)!);
      if (y != null && mo != null && d != null) {
        return DateTime(y, mo, d);
      }
    }
    try {
      return DateTime.parse(t);
    } catch (_) {
      return null;
    }
  }

  Widget _buildConfigureGuide() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.sensors_off_rounded,
          size: 54,
          color: labelText.withValues(alpha: 0.45),
        ),
        const SizedBox(height: 14),
        Text(
          'Sensor not configured',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: headingText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set up the sensor to see the probe ID, calibration and permitted range.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.35, color: labelText),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: onConfigure,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Configure sensor'),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlipCard() {
    final s = slip!;
    return GestureDetector(
      onTap: onSlipTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A66FF), Color(0xFF0052D4)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A66FF).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.assignment_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            // Title + BC
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Current Process Details",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    "BTY Code: ${s.batteryCode}  •  BTY No(s): ${s.batteryFrom} – ${s.batteryTo}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Arrow
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoProductionCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF78909C), Color(0xFF546E7A)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.pause_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Production Status",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  "No Production",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    required this.isLive,
    this.showRange = true,
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
  final bool isLive;
  final bool showRange;

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
    color: dewLabelText.withValues(alpha: 0.7),
    letterSpacing: 0.5,
  );

  TextStyle get _updatedStyle => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFF7A8AA6),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 300,
        maxWidth: 480,
        minHeight: 200,
      ),
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A8DFF).withValues(alpha: 0.12),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLive
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLive
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFBDBDBD),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF757575),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive ? 'LIVE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isLive
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF757575),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                            dewPointDisplay,
                            style: _bigNumberStyle.copyWith(fontSize: 42),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("Dew Point", style: _ppmLabelStyle),
                  ],
                ),
              ),

              Container(
                height: 50,
                width: 2,
                color: const Color(0xFFE2E8F0),
                margin: const EdgeInsets.symmetric(horizontal: 24),
              ),

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

          if (showRange)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12.0),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
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
                      color: dewLabelText.withValues(alpha: 0.8),
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
                      ),
                      _buildMinMax("Max", maxVal),
                    ],
                  ),
                ],
              ),
            ),

          Align(
            alignment: Alignment.centerLeft,
            child: Text('Updated At: $updatedAt', style: _updatedStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildMinMax(String label, String val) {
    final displayVal = val.isEmpty ? '--' : '$val °C';
    return Column(
      children: [
        Text(
          displayVal,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: dewBigNumber,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: dewLabelText.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ProcessSlipButton extends StatefulWidget {
  final ProcessSlip slip;
  final VoidCallback onToggle;

  const _ProcessSlipButton({required this.slip, required this.onToggle});

  @override
  State<_ProcessSlipButton> createState() => _ProcessSlipButtonState();
}

class _ProcessSlipButtonState extends State<_ProcessSlipButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white24,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A66FF),
                    Color(0xFF0052D4),
                    Color(0xFF1A3A8A),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF0A66FF,
                    ).withValues(alpha: 0.25 + (_pulseAnimation.value * 0.15)),
                    blurRadius: 16 + (_pulseAnimation.value * 8),
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assignment_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              // Text content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Current Process Details",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "BTY Code: ${widget.slip.batteryCode}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Separator
              Container(
                width: 1,
                height: 28,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 14),
              // Battery No badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  "BTY NO: ${widget.slip.batteryFrom} - ${widget.slip.batteryTo}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Arrow indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProcessSlipContent extends StatelessWidget {
  final ProcessSlip slip;
  final String workstationName;
  final bool showAll;
  final VoidCallback onToggleShowAll;
  final VoidCallback onClose;

  const _ProcessSlipContent({
    required this.slip,
    required this.workstationName,
    required this.showAll,
    required this.onToggleShowAll,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 15),
          ),
        ],
        border: Border.all(color: const Color(0xFFE1E8FF), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Flexible(child: SingleChildScrollView(child: _buildTable(context))),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_rounded,
            color: Color(0xFF0A66FF),
            size: 28,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Process Identification Document (PID)",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C3366),
                ),
              ),
              Text(
                "Battery Code: ${slip.batteryCode} | PID: ${slip.pidNumber} | CLN: ${slip.clnNumber}",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A6B8A),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(
              Icons.cancel_rounded,
              color: Colors.redAccent,
              size: 32,
            ),
            tooltip: 'Close Slip',
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final rowsToDisplay = showAll
        ? slip.rows
        : slip.rows.where((row) => _shouldHighlight(row.type)).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.0),
          3: FlexColumnWidth(1.8),
          4: FlexColumnWidth(1.8),
          5: FlexColumnWidth(1.5),
          6: FlexColumnWidth(1.5),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(8),
            ),
            children: [
              _cell("Pellet Name", isHeader: true),
              _cell("Lot No", isHeader: true),
              _cell("Dia (mm)", isHeader: true),
              _cell("Weight Range (g)", isHeader: true),
              _cell("Thk Range (mm)", isHeader: true),
              _cell("Pressure (kg/cm²)", isHeader: true),
              _cell("Time (s)", isHeader: true),
            ],
          ),
          ...rowsToDisplay.map((row) {
            final isHighlighted = _shouldHighlight(row.type);

            final wtT = double.tryParse(row.wtT) ?? 0;
            final wtTol = double.tryParse(row.wtTol) ?? 0;
            final thT = double.tryParse(row.thT) ?? 0;
            final thTol = double.tryParse(row.thTol) ?? 0;

            final wtRange = wtT > 0
                ? "${(wtT - wtTol).toStringAsFixed(2)} - ${(wtT + wtTol).toStringAsFixed(2)}"
                : row.wtT;
            final thRange = thT > 0
                ? "${(thT - thTol).toStringAsFixed(2)} - ${(thT + thTol).toStringAsFixed(2)}"
                : row.thT;

            return TableRow(
              decoration: BoxDecoration(
                color: isHighlighted ? const Color(0xFFFFF9C4) : null,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              children: [
                _cell(row.name, isBold: isHighlighted),
                _cell(row.lot),
                _cell(row.dia),
                _cell(wtRange),
                _cell(thRange),
                _cell(row.press),
                _cell(row.time),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: onToggleShowAll,
            icon: Icon(
              showAll ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
            ),
            label: Text(showAll ? "Filter" : "Show All"),
          ),
          Text(
            "Battery No(s): ${slip.batteryFrom} - ${slip.batteryTo}",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0A66FF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool isHeader = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isHeader ? 14 : 14,
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? const Color(0xFF1C3366) : Colors.black87,
        ),
      ),
    );
  }

  bool _shouldHighlight(String rowType) {
    if (slip.workstationRoles.isEmpty) return false;
    return slip.workstationRoles.any(
      (mappedType) =>
          rowType.toLowerCase().contains(mappedType.toLowerCase()) ||
          mappedType.toLowerCase().contains(rowType.toLowerCase()),
    );
  }
}
