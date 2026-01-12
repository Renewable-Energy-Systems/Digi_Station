// lib/screens/gauge_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../socket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/api_constants.dart';
import '../services/config_service.dart';
import 'det_selector_screen.dart';
import 'settings_screen.dart';

class GaugeScreen extends StatefulWidget {
  const GaugeScreen({super.key});

  @override
  State<GaugeScreen> createState() => _GaugeScreenState();
}

class _GaugeScreenState extends State<GaugeScreen> with AutomaticKeepAliveClientMixin {
  String _thicknessValue = "--.---";
  String _weightValue = "--.--";
  bool isConnected = false;
  StreamSubscription? _gaugeSub;
  String _machineName = "Unknown";
  String _machineIp = "";
  
  // Pi Health
  String _piTempValue = "--";
  bool? _piThrottled;

  // WebSocket channel for DET selector & updates
  WebSocketChannel? _detChannel;
  final String detWsUrl = ApiConstants.detWsUrl; 
  final String apiHost = ApiConstants.detApiHost; 

  @override
  void initState() {
    super.initState();
    _loadConfig();

    // 1) Subscribe to connection status
    SocketService().connectionStatus.listen((status) {
       if (mounted) {
         setState(() {
           isConnected = status;
         });
       }
    });

    // 2) existing gauge data subscription
    _gaugeSub = SocketService().gaugeStream.listen((data) {
      print("Received Data: $data"); // Debug log within the app logic
      
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
           if (data.containsKey('value') && !data.containsKey('height') && !data.containsKey('weight')) {
             _thicknessValue = data['value'].toString();
           }
        });
      }
    });

    // 3) Connect socket
    _connectSocket();

    // 4) create a WS channel dedicated for DET subscriptions & UI
    try {
      _detChannel = IOWebSocketChannel.connect(detWsUrl);
      _detChannel!.stream.listen(
        (msg) {
        },
        onError: (err) {
          debugPrint('DET WS error: $err');
        },
        onDone: () {
          debugPrint('DET WS closed');
        },
      );
    } catch (_) { // Add catch block
       // ignore or log
       _detChannel = null;
    }
  }

  Future<void> _loadConfig() async {
    final name = await ConfigService().getSavedMachineType();
    setState(() {
      _machineName = name ?? "Select Machine"; // Use placeholder if null
    });
  }

  Future<void> _connectSocket() async {
    final url = await ConfigService().getBaseUrl();
    if (url == null) {
      // If no URL selected, ensure disconnected and UI shows 'Select'
      SocketService().disconnect(); 
      setState(() {
        _machineIp = "";
        isConnected = false;
      });
      return;
    }

    setState(() {
      _machineIp = url;
      // Reset data on switch to prevent mixing
      _thicknessValue = "--.---";
      _weightValue = "--.--";
    });
    SocketService().connect(url);
  }

  @override
  void dispose() {
    _gaugeSub?.cancel();
    try {
      _detChannel?.sink.close();
    } catch (_) {}
    _detChannel = null;
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
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _machineName == "Unknown" || _machineName == "Select Machine" ? null : _machineName,
            hint: const Text(
              "Select Machine",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
            isExpanded: false,
            items: ConfigService.machineUrls.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      entry.value.replaceAll("http://", "").replaceAll(":5050", ""),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (String? newValue) async {
              if (newValue != null) {
                // Update Config
                await ConfigService().saveMachineType(newValue);
                // Update UI & Connect
                _loadConfig();
                _connectSocket();
              }
            },
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                // Sync back if changed in settings
                _loadConfig();
                _connectSocket();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: const Icon(Icons.settings, color: Colors.blueGrey, size: 24),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection Status Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isConnected ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: isConnected ? Colors.green[700] : Colors.red[700],
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected ? "Connected to $_machineName" : "Connecting to $_machineName...",
                          style: TextStyle(
                            fontSize: 14,
                            color: isConnected ? Colors.green[900] : Colors.red[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_machineIp.isNotEmpty)
                          Text(
                            _machineIp,
                            style: TextStyle(
                              fontSize: 12,
                              color: isConnected ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Combined Thickness and Weight Card
              _buildCombinedCard(
                title1: "THICKNESS",
                value1: _thicknessValue,
                unit1: "mm",
                color1: const Color(0xFF0A66FF),
                title2: "WEIGHT",
                value2: _weightValue,
                unit2: "g",
                color2: const Color(0xFFFF9800),
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
            color: Colors.black.withOpacity(0.05),
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
          ]
        ],
      ),
    );
  }

  Widget _buildCombinedCard({
    required String title1,
    required String value1,
    required String unit1,
    required Color color1,
    required String title2,
    required String value2,
    required String unit2,
    required Color color2,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildValueColumn(title1, value1, unit1, color1)),
          Container(
            width: 1, 
            height: 80, 
            color: Colors.grey.withOpacity(0.2),
          ),
          Expanded(child: _buildValueColumn(title2, value2, unit2, color2)),
        ],
      ),
    );
  }

  Widget _buildValueColumn(String title, String value, String unit, Color color) {
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
}
