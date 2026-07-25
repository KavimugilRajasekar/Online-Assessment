import 'package:flutter/material.dart';

class BwbTheme {
  BwbTheme._();

  static const Color primary = Color(0xFF2563EB); // Modern Blue
  static const Color primaryVariant = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF10B981); // Emerald
  static const Color bg = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color text = Color(0xFF0F172A); // Slate 900
  static const Color muted = Color(0xFF64748B); // Slate 500
  static const Color correct = Color(0xFF10B981);
  static const Color wrong = Color(0xFFEF4444); // Red 500
  static const Color unanswered = Color(0xFF94A3B8); // Slate 400

  static const String fontFamily = 'Comfortaa';
  static const String accentFont = 'PlaywriteUSModern';

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        secondary: secondary,
        error: wrong,
        surface: surface,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: text,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(color: border, width: 1),
        ),
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontFamily: fontFamily, color: text, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(fontFamily: fontFamily, color: text, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(fontFamily: fontFamily, color: text, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontFamily: fontFamily, color: text),
        bodyMedium: TextStyle(fontFamily: fontFamily, color: text),
        bodySmall: TextStyle(fontFamily: fontFamily, color: muted),
        labelLarge: TextStyle(fontFamily: fontFamily, color: text, fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(color: border),
    );
  }
}
