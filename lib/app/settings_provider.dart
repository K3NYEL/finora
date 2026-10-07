import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_preferences.dart';

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.dark,
    this.animationsEnabled = true,
  });

  final ThemePreference theme;
  final bool animationsEnabled;

  AppSettings copyWith({
    ThemePreference? theme,
    bool? animationsEnabled,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
    );
  }

  ThemeMode get themeMode {
    switch (theme) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final theme = await AppPreferences.getTheme();
    final animations = await AppPreferences.getAnimations();

    state = AppSettings(
      theme: theme,
      animationsEnabled: animations,
    );
  }

  Future<void> setTheme(ThemePreference theme) async {
    state = state.copyWith(theme: theme);
    await AppPreferences.setTheme(theme);
  }

  Future<void> setAnimations(bool enabled) async {
    state = state.copyWith(
      animationsEnabled: enabled,
    );

    await AppPreferences.setAnimations(enabled);
  }
}
