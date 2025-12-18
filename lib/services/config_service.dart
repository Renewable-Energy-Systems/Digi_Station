import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _keyMachineType = 'machine_type';

  // Map of Machine Type to IP Address (Base URL)
  static const Map<String, String> machineUrls = {
    'EPM': 'http://192.168.0.201:5050',
    'CPM': 'http://192.168.0.202:5050',
    'APM': 'http://192.168.0.203:5050',
    'HPM': 'http://192.168.0.204:5050',
  };

  Future<String?> getSavedMachineType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMachineType); // No default
  }

  Future<void> saveMachineType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMachineType, type);
  }

  Future<String?> getBaseUrl() async {
    final type = await getSavedMachineType();
    if (type == null) return null;
    return machineUrls[type];
  }

  // Baked-in Token from --dart-define
  static const String gitHubToken = String.fromEnvironment('GITHUB_TOKEN');
}
