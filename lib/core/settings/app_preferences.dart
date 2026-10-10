import 'package:shared_preferences/shared_preferences.dart';
import '../utils/currency_utils.dart';

class AppPreferences {
  AppPreferences._();

  static const _themeKey = 'theme_mode';
  static const _animationsKey = 'animations_enabled';
  static const _currencyKey = 'finance_currency';
  static const _autoBackupFrequencyKey = 'auto_backup_frequency';
  static const _autoBackupLastAtKey = 'auto_backup_last_at';

  static Future<String> getAutoBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_autoBackupFrequencyKey) ?? 'disabled';
    return const {'disabled', 'daily', 'weekly'}.contains(value) ? value : 'disabled';
  }

  static Future<void> setAutoBackupFrequency(String value) async {
    if (!const {'disabled', 'daily', 'weekly'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Frecuencia no compatible');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoBackupFrequencyKey, value);
  }

  static Future<DateTime?> getLastAutoBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_autoBackupLastAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  static Future<void> setLastAutoBackupAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoBackupLastAtKey, value.toUtc().toIso8601String());
  }

  static Future<String> getCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_currencyKey) ?? 'DOP';
    return const {'DOP', 'USD', 'EUR'}.contains(value) ? value : 'DOP';
  }

  static Future<void> setCurrency(String code) async {
    if (!const {'DOP', 'USD', 'EUR'}.contains(code)) {
      throw ArgumentError.value(code, 'code', 'Moneda no compatible');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, code);
    setCurrencyCodeInMemory(code);
  }

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
