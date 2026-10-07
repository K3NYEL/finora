import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.error,
        )
      : const ColorScheme.light(
          primary: AppColors.primary,
          surface: Colors.white,
          onSurface: Colors.black87,
          error: AppColors.error,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? AppColors.background : const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: isDark ? AppColors.surface : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.surface : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
