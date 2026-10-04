import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.light,
      primary: const Color(0xFF6D4AE9),
      secondary: const Color(0xFF8B5CF6),
      tertiary: const Color(0xFFF59E0B),
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F3FF),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Color(0xFF1F2937),
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shadowColor: const Color(0x1A6D4AE9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIconColor: const Color(0xFF6B7280),
      hintStyle: const TextStyle(color: Color(0xFF6B7280)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF7C4DFF), width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6D4AE9),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      backgroundColor: const Color(0xFFF3E8FF),
      side: BorderSide.none,
      labelStyle: const TextStyle(color: Color(0xFF4C1D95)),
      secondaryLabelStyle: const TextStyle(color: Color(0xFF4C1D95)),
      brightness: Brightness.light,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
  );
}
