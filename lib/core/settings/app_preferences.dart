import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();

  static const _themeKey = 'theme_mode';
  static const _animationsKey = 'animations_enabled';

  static Future<ThemePreference> getTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_themeKey);

    switch (value) {
      case 'light':
        return ThemePreference.light;
      case 'dark':
        return ThemePreference.dark;
      default:
        return ThemePreference.system;
    }
  }

  static Future<void> setTheme(ThemePreference theme) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _themeKey,
      theme.name,
    );
  }

  static Future<bool> getAnimations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_animationsKey) ?? true;
  }

  static Future<void> setAnimations(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _animationsKey,
      enabled,
    );
  }
}

enum ThemePreference {
  system,
  light,
  dark,
}
