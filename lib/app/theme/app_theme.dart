import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final primary = isDark ? AppColors.primary : const Color(0xFF0369A1);
  final background =
      isDark ? AppColors.background : const Color(0xFFF1F5F9);
  final surface = isDark ? AppColors.surface : Colors.white;
  final text = isDark ? AppColors.textPrimary : const Color(0xFF0F172A);
  final muted = isDark ? AppColors.textSecondary : const Color(0xFF475569);
  final outline = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

  final colorScheme = (isDark
          ? const ColorScheme.dark()
          : const ColorScheme.light())
      .copyWith(
    primary: primary,
    onPrimary: Colors.white,
    secondary: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0E7490),
    onSecondary: Colors.white,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
    error: isDark ? AppColors.error : const Color(0xFFB91C1C),
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor:
          isDark ? const Color(0xFF164E63) : const Color(0xFFE0F2FE),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? primary : muted,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor:
          isDark ? const Color(0xFF164E63) : const Color(0xFFE0F2FE),
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(color: muted),
      selectedLabelTextStyle: TextStyle(color: primary),
      unselectedLabelTextStyle: TextStyle(color: muted),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
  );
}
