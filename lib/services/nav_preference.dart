import 'package:shared_preferences/shared_preferences.dart';

/// The user's preferred navigation app for the "Go now" action.
/// [ask] means show the picker each time (and remember the next pick).
enum NavApp {
  ask('Ask', 'Ask each time'),
  apple('Apple', 'Apple Maps'),
  google('Google', 'Google Maps'),
  waze('Waze', 'Waze');

  const NavApp(this.shortLabel, this.label);

  /// Compact label for segmented controls.
  final String shortLabel;

  /// Full label for menus and the directions sheet.
  final String label;
}

const String _navAppPrefKey = 'driverintel.navApp';

/// Returns the saved preference, or [NavApp.ask] if none has been chosen.
Future<NavApp> getPreferredNavApp() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_navAppPrefKey);
  for (final app in NavApp.values) {
    if (app.name == name) return app;
  }
  return NavApp.ask;
}

/// Persists the preference. [NavApp.ask] clears it so the picker shows again.
Future<void> setPreferredNavApp(NavApp app) async {
  final prefs = await SharedPreferences.getInstance();
  if (app == NavApp.ask) {
    await prefs.remove(_navAppPrefKey);
  } else {
    await prefs.setString(_navAppPrefKey, app.name);
  }
}
