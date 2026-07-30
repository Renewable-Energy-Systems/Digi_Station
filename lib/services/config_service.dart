import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/api_constants.dart';

class ConfigService {
  static const String _keyMachineType = 'machine_type';

  // Map of Machine Type to IP Address (Base URL)
  static const Map<String, String> machineUrls = {
    'HPM': 'http://192.168.0.201:5050',
    'CPM': 'http://192.168.0.202:5050',
    'APM': 'http://192.168.0.203:5050',
    'EPM': 'http://192.168.0.204:5050',
  };

  static const String _keyWorkstationId = 'workstation_id';
  static const String _keyWorkstationRole = 'workstation_role';
  static const String _keyUseProductionApi = 'use_production_api';
  static const String _keyStationApiEnabled = 'station_api_enabled';
  static const String _keyDewpointHost = 'dewpoint_host';

  /// The Dewpoint live-feed server as "IP:port" (the WebSocket + HTTP sensor
  /// API share it). Defaults to the bundled LAN IP; override it in Settings so a
  /// network IP change doesn't require rebuilding/redeploying the APK.
  Future<String> getDewpointHost() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyDewpointHost);
    return (v == null || v.trim().isEmpty)
        ? ApiConstants.defaultDewpointHost
        : v.trim();
  }

  Future<void> saveDewpointHost(String hostPort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDewpointHost, hostPort.trim());
  }

  Future<String> getDetWsUrl() async => 'ws://${await getDewpointHost()}';
  Future<String> getDetApiHost() async => 'http://${await getDewpointHost()}';

  Future<String?> getSavedMachineType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMachineType); // No default
  }

  Future<void> saveMachineType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMachineType, type);
  }

  Future<String?> getWorkstationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWorkstationId);
  }

  Future<void> saveWorkstationId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWorkstationId, id);
  }

  Future<String?> getWorkstationRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWorkstationRole);
  }

  Future<void> saveWorkstationRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWorkstationRole, role);
  }

  Future<bool> shouldUseProductionApi() async {
    // Release builds always use the (secured) production API — the LOCAL option
    // is a development convenience only.
    if (kReleaseMode) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseProductionApi) ?? false;
  }

  Future<void> saveUseProductionApi(bool useProd) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseProductionApi, useProd);
  }

  /// Whether this station uses the ops API (workstation list + live process
  /// slips). Stations that don't need it can turn it off so the app never
  /// contacts the ops server (avoiding unnecessary errors). Defaults to ON.
  Future<bool> isStationApiEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyStationApiEnabled) ?? true;
  }

  Future<void> saveStationApiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStationApiEnabled, enabled);
  }

  Future<String> getOpsDigiBaseUrl() async {
    final useProd = await shouldUseProductionApi();
    return useProd 
        ? ApiConstants.productionOpsDigiBaseUrl 
        : ApiConstants.opsDigiBaseUrl;
  }

  Future<List<Map<String, dynamic>>> fetchWorkstations() async {
    try {
      final baseUrl = await getOpsDigiBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/api_workstations.php'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // List of enabled Video IDs for this device
  static const String _keyEnabledVideoIds = 'enabled_video_ids';

  Future<List<String>> getEnabledVideoIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyEnabledVideoIds) ?? [];
  }

  Future<void> saveEnabledVideoIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyEnabledVideoIds, ids);
  }

  Future<String?> getBaseUrl() async {
    final type = await getSavedMachineType();
    if (type == null) return null;
    return machineUrls[type];
  }

  // Baked-in Token from --dart-define
  static const String gitHubToken = String.fromEnvironment('GITHUB_TOKEN');
}
