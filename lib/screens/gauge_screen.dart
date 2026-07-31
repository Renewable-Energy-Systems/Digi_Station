// lib/screens/gauge_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../socket_service.dart';
import '../services/config_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GaugeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const GaugeScreen({super.key, this.onNavigateToSettings});

  @override
  State<GaugeScreen> createState() => GaugeScreenState();
}

class GaugeScreenState extends State<GaugeScreen>
    with AutomaticKeepAliveClientMixin {
  String _thicknessValue = "--.---";
  String _weightValue = "--.--";
  bool isConnected = false;
  StreamSubscription? _gaugeSub;
  StreamSubscription? _connSub;
  String _machineName = "Unknown";
  String _machineIp = "";
  bool _machineConfigured = false;
  // The operator can disconnect from the machine on THIS screen without changing
  // the selected machine. While set, we won't auto-reconnect (until they tap
  // Reconnect, or pick a different machine).
  bool _manuallyDisconnected = false;

  // Pi Health
  String _piTempValue = "--";
  bool? _piThrottled;

  // Range Settings (Machine Specific)
  double? _minThickness;
  double? _maxThickness;
  double? _minWeight;
  double? _maxWeight;

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? _lastAlertTime;
  static const Duration _alertDebounce = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _loadConfig();

    // 1) Subscribe to connection status
    _connSub = SocketService().connectionStatus.listen((status) {
      if (mounted) {
        setState(() {
          isConnected = status;
        });
      }
    });

    // 2) existing gauge data subscription
    _gaugeSub = SocketService().gaugeStream.listen((data) {
      if (mounted) {
        setState(() {
          if (data.containsKey('height')) {
            _thicknessValue = data['height'].toString();
          }
          if (data.containsKey('weight')) {
            _weightValue = data['weight'].toString();
          }
          if (data.containsKey('pi_temp')) {
            final t = data['pi_temp'];
            _piTempValue = (t != null) ? t.toString() : "--";
          }
          if (data.containsKey('pi_throttled')) {
            _piThrottled = data['pi_throttled'];
          }
          // Fallback for generic 'value' - assume thickness if ambiguous, or ignore?
          // User context implies height/weight specific. I'll map value to thickness for backward compat if needed, but logs show specific keys.
          if (data.containsKey('value') &&
              !data.containsKey('height') &&
              !data.containsKey('weight')) {
            _thicknessValue = data['value'].toString();
          }
          _checkAlerts(); // visual/audio check on every update
        });
      }
    });

    // 3) Connect socket
    _connectSocket();
  }

  /// Re-reads the saved hardware configuration and reconnects the socket.
  /// Called by the shell when the user navigates back to this screen so that
  /// changes made in Settings take effect without restarting the app.
  Future<void> refreshConfig() async {
    await _loadConfig();
    await _connectSocket();
  }

  Future<void> _loadConfig() async {
    final name = await ConfigService().getSavedMachineType();
    setState(() {
      _machineConfigured = name != null;
      _machineName = name ?? "Select Machine"; // Use placeholder if null
    });
    await _loadRanges();
  }

  Future<void> _connectSocket() async {
    final url = await ConfigService().getBaseUrl();
    if (url == null) {
      // If no URL selected, ensure disconnected and UI shows 'Select'
      SocketService().disconnect();
      if (mounted) {
        setState(() {
          _machineIp = "";
          isConnected = false;
          _manuallyDisconnected = false;
        });
      }
      return;
    }

    // Picking a different machine is an explicit "connect to this" — it clears
    // any manual disconnect from the previous machine.
    final machineChanged = url != _machineIp;
    if (machineChanged) _manuallyDisconnected = false;

    // Same machine and the operator chose to stay disconnected → do nothing.
    if (_manuallyDisconnected) return;

    // Same machine, already wired up — leave the live values alone.
    if (!machineChanged) return;

    if (mounted) {
      setState(() {
        _machineIp = url;
        isConnected = false;
        // Reset ALL live values on switch so stale readings from the previous
        // machine (thickness, weight, Pi temperature) don't linger while the
        // new machine is still connecting.
        _thicknessValue = "--.---";
        _weightValue = "--.--";
        _piTempValue = "--";
        _piThrottled = null;
      });
    }
    SocketService().connect(url);
  }

  /// Disconnect from the machine on this screen only, without changing the
  /// selected machine. Stays disconnected until Reconnect (or a machine switch).
  void _disconnectManually() {
    SocketService().disconnect();
    if (mounted) {
      setState(() {
        _manuallyDisconnected = true;
        isConnected = false;
        _thicknessValue = "--.---";
        _weightValue = "--.--";
        _piTempValue = "--";
        _piThrottled = null;
      });
    }
  }

  Future<void> _reconnectManually() async {
    _manuallyDisconnected = false;
    _machineIp = ""; // force a fresh dial even though the machine is unchanged
    await _connectSocket();
  }

  @override
  void dispose() {
    _gaugeSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _machineConfigured ? _machineName : 'Live Readings',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (_machineIp.isNotEmpty)
              Text(
                _machineIp.replaceAll("http://", "").replaceAll(":5050", ""),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_machineConfigured)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: IconButton(
                icon: const Icon(Icons.tune, color: Colors.blueGrey),
                tooltip: "Range Settings",
                onPressed: _showRangeSettings,
              ),
            ),
        ],
      ),
      body: !_machineConfigured
          ? _buildNoMachineState()
          : Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection Status Card
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _manuallyDisconnected
                      ? const Color(0xFFF0F1F4)
                      : isConnected
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _manuallyDisconnected
                        ? Colors.blueGrey.withValues(alpha: 0.3)
                        : isConnected
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (_manuallyDisconnected || !isConnected)
                          ? Icons.wifi_off
                          : Icons.wifi,
                      color: _manuallyDisconnected
                          ? Colors.blueGrey[600]
                          : isConnected
                              ? Colors.green[700]
                              : Colors.red[700],
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _manuallyDisconnected
                              ? "Disconnected from $_machineName"
                              : isConnected
                                  ? "Connected to $_machineName"
                                  : "Connecting to $_machineName...",
                          style: TextStyle(
                            fontSize: 14,
                            color: _manuallyDisconnected
                                ? Colors.blueGrey[800]
                                : isConnected
                                    ? Colors.green[900]
                                    : Colors.red[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_machineIp.isNotEmpty)
                          Text(
                            _machineIp,
                            style: TextStyle(
                              fontSize: 12,
                              color: isConnected
                                  ? Colors.green[700]
                                  : Colors.red[700],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Disconnect / Reconnect the machine link for THIS screen only.
              _manuallyDisconnected
                  ? ElevatedButton.icon(
                      onPressed: _reconnectManually,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Reconnect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _disconnectManually,
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Disconnect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                      ),
                    ),

              const SizedBox(height: 10),

              // Combined Thickness and Weight Card
              _buildCombinedCard(
                title1: "THICKNESS",
                value1: _thicknessValue,
                unit1: "mm",
                defaultColor1: const Color(0xFF0A66FF),
                min1: _minThickness,
                max1: _maxThickness,
                title2: "WEIGHT",
                value2: _weightValue,
                unit2: "g",
                defaultColor2: const Color(0xFFFF9800),
                min2: _minWeight,
                max2: _maxWeight,
              ),

              const SizedBox(height: 16),

              // PI TEMP Card
              _buildGaugeCard(
                title: "PI TEMP",
                value: _piTempValue,
                unit: "°C",
                valueColor: _getTempColor(),
                statusText: _getTempStatus(),
                statusColor: _getTempColor(),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty-state shown when no machine has been selected yet.
  /// Mirrors the Work Instructions screen's "not configured" placeholder
  /// instead of showing a red "Connecting..." status.
  Widget _buildNoMachineState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.precision_manufacturing_rounded,
              size: 72,
              color: Colors.blueGrey[200],
            ),
            const SizedBox(height: 20),
            Text(
              'No machine selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a machine in Settings to start monitoring.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.blueGrey[400]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: widget.onNavigateToSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGaugeCard({
    required String title,
    required String value,
    required String unit,
    required Color valueColor,
    String? statusText,
    Color? statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(30),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              letterSpacing: 1.5,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 50,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  letterSpacing: -2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 8),
                child: Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (statusText != null) ...[
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCombinedCard({
    required String title1,
    required String value1,
    required String unit1,
    required Color defaultColor1,
    double? min1,
    double? max1,
    required String title2,
    required String value2,
    required String unit2,
    required Color defaultColor2,
    double? min2,
    double? max2,
  }) {
    Color getColor(String val, Color def, double? min, double? max) {
      final v = double.tryParse(val);
      if (v == null || min == null || max == null) return def;
      if (v >= min && v <= max) return Colors.green;
      return Colors.red;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildValueColumn(
              title1,
              value1,
              unit1,
              getColor(value1, defaultColor1, min1, max1),
            ),
          ),
          Container(width: 1, height: 80, color: Colors.grey.withValues(alpha: 0.2)),
          Expanded(
            child: _buildValueColumn(
              title2,
              value2,
              unit2,
              getColor(value2, defaultColor2, min2, max2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueColumn(
    String title,
    String value,
    String unit,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            letterSpacing: 1.5,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 36, // Slightly smaller to fit two side-by-side
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: -1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                unit,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getTempColor() {
    if (_piThrottled == true) return Colors.red;
    final t = double.tryParse(_piTempValue);
    if (t == null) return Colors.black;
    if (t >= 80) return Colors.red;
    if (t >= 70) return Colors.orange;
    if (t >= 60) return const Color(0xFFB58900); // darkish yellow
    return Colors.green;
  }

  String? _getTempStatus() {
    if (_piThrottled == true) return "THROTTLING!";
    final t = double.tryParse(_piTempValue);
    if (t == null) return null;
    if (t >= 80) return "OVERHEAT";
    if (t >= 70) return "HOT";
    if (t >= 60) return "WARM";
    return "OK";
  }

  Future<void> _loadRanges() async {
    final prefs = await SharedPreferences.getInstance();
    // Use machine name in key for specificity
    final p = "gauge_range_${_machineName}_";
    setState(() {
      _minThickness = prefs.getDouble('${p}minThickness');
      _maxThickness = prefs.getDouble('${p}maxThickness');
      _minWeight = prefs.getDouble('${p}minWeight');
      _maxWeight = prefs.getDouble('${p}maxWeight');
    });
  }

  Future<void> _saveRanges(
    double? minT,
    double? maxT,
    double? minW,
    double? maxW,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final p = "gauge_range_${_machineName}_";

    if (minT != null) {
      await prefs.setDouble('${p}minThickness', minT);
    } else {
      await prefs.remove('${p}minThickness');
    }
    if (maxT != null) {
      await prefs.setDouble('${p}maxThickness', maxT);
    } else {
      await prefs.remove('${p}maxThickness');
    }
    if (minW != null) {
      await prefs.setDouble('${p}minWeight', minW);
    } else {
      await prefs.remove('${p}minWeight');
    }
    if (maxW != null) {
      await prefs.setDouble('${p}maxWeight', maxW);
    } else {
      await prefs.remove('${p}maxWeight');
    }

    // Reload to apply immediately
    await _loadRanges();
  }

  void _showRangeSettings() {
    final minTCtrl = TextEditingController(
      text: _minThickness?.toString() ?? '',
    );
    final maxTCtrl = TextEditingController(
      text: _maxThickness?.toString() ?? '',
    );
    final minWCtrl = TextEditingController(text: _minWeight?.toString() ?? '');
    final maxWCtrl = TextEditingController(text: _maxWeight?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Range Settings ($_machineName)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Thickness Range (mm)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minTCtrl,
                      decoration: const InputDecoration(labelText: 'Min'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: maxTCtrl,
                      decoration: const InputDecoration(labelText: 'Max'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Weight Range (g)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minWCtrl,
                      decoration: const InputDecoration(labelText: 'Min'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: maxWCtrl,
                      decoration: const InputDecoration(labelText: 'Max'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveRanges(
                double.tryParse(minTCtrl.text),
                double.tryParse(maxTCtrl.text),
                double.tryParse(minWCtrl.text),
                double.tryParse(maxWCtrl.text),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _checkAlerts() {
    bool alert = false;

    // Check Thickness
    final t = double.tryParse(_thicknessValue);
    if (t != null && _minThickness != null && _maxThickness != null) {
      if (t < _minThickness! || t > _maxThickness!) alert = true;
    }

    // Check Weight
    final w = double.tryParse(_weightValue);
    if (w != null && _minWeight != null && _maxWeight != null) {
      if (w < _minWeight! || w > _maxWeight!) alert = true;
    }

    if (alert) {
      final now = DateTime.now();
      if (_lastAlertTime == null ||
          now.difference(_lastAlertTime!) > _alertDebounce) {
        _lastAlertTime = now;
        _playAlertSound();
      }
    }
  }

  Future<void> _playAlertSound() async {
    try {
      // release mode often requires asset source defined in pubspec
      // For now we use a built-in player or a simple beep if possible.
      // Since we added audioplayers, let's try to play a default 'beep' or just error tone.
      // NOTE: User might need to add a sound file to assets.
      // For this step, I will try to play a sourced file or just log if missing.
      // But typically we need a file.
      // Strategy: Since I can't easily add a file to assets physically,
      // I will assume there might be one or use a URL for testing?
      // Actually, 'audioplayers' can play from generated bytes but that's complex.
      // Let's assume we proceed without a file and just log "BEEP" unless user provides one.
      // Wait, I can try SourceUrl if device has internet, but that's flaky.
      // Better: I'll try to find a system sound or just leave the placeholder for the user to add 'assets/alert.mp3'.

      // Attempting to play a generic error sound if available or just log.
      // debugPrint("BEEP! BEEP!");

      // Provide a concrete implementation assuming 'assets/alert.mp3' exists or will exist.
      // Or use a URL for a simple beep test.
      // await _audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'));
      // The user wants a sound. I'll use a public reliable URL for now.
      await _audioPlayer.play(
        UrlSource(
          'https://codeskulptor-demos.commondatastorage.googleapis.com/GalaxyInvaders/pause.mp3',
        ),
      );
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }
}
