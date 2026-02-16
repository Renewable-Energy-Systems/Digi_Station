import 'package:shared_preferences/shared_preferences.dart';

enum AppScreen { webLogs, home, wiList, gauge, detSelector, settings }

class ScreenConfigService {
  static const String _keyVisibleScreens = 'visible_screen_ids';

  // Default: ALL screens enabled
  static const List<AppScreen> defaultScreens = [
    AppScreen.webLogs,
    AppScreen.home,
    AppScreen.wiList,
    AppScreen.gauge,
    AppScreen.detSelector,
    AppScreen.settings,
  ];

  // Helper to get ID (string) from enum
  String _screenId(AppScreen screen) => screen.name; // e.g., "webLogs"

  // Helper to get Enum from ID
  AppScreen? _screenFromId(String id) {
    try {
      return AppScreen.values.firstWhere((e) => e.name == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<AppScreen>> getEnabledScreens() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? ids = prefs.getStringList(_keyVisibleScreens);

    if (ids == null) {
      return List.from(defaultScreens); // Return a mutable copy
    }

    final List<AppScreen> screens = [];
    for (final id in ids) {
      final s = _screenFromId(id);
      if (s != null) screens.add(s);
    }

    // Safety check: ensure HOME is always there?
    // Actually, let's trust the saved list, but if empty, maybe revert to home only?
    // For now, if empty list is saved (user disabled all), they get nothing but maybe blank scaffold?
    // Always sort to ensure consistent order
    screens.sort((a, b) => a.index.compareTo(b.index));

    return screens;
  }

  Future<void> saveEnabledScreens(List<AppScreen> screens) async {
    final prefs = await SharedPreferences.getInstance();

    // Sort to maintain navigation order
    screens.sort((a, b) => a.index.compareTo(b.index));

    final List<String> ids = screens.map((s) => _screenId(s)).toList();
    await prefs.setStringList(_keyVisibleScreens, ids);
  }
}
