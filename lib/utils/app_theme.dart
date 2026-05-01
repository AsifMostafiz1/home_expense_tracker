import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF6200EE);
  static const Color primaryLight = Color(0xFFBB86FC);

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: primaryColor,
    ),
    scaffoldBackgroundColor: Colors.white,
    cardColor: Colors.white,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.bold, height: 1.2),
      headlineMedium: TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: Colors.black87, fontSize: 16),
      bodyMedium: TextStyle(color: Colors.black54, fontSize: 14),
      bodySmall: TextStyle(color: Colors.black54, fontSize: 13),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[100],
      hintStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      prefixIconColor: Colors.black54,
      suffixIconColor: Colors.black54,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
      ),
    ),
    dividerColor: Colors.grey[200],
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primaryLight,
      secondary: primaryLight,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.2),
      headlineMedium: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
      bodySmall: TextStyle(color: Colors.white70, fontSize: 13),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      hintStyle: const TextStyle(fontSize: 14, color: Colors.white70),
      prefixIconColor: Colors.white70,
      suffixIconColor: Colors.white70,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryLight,
        foregroundColor: Colors.black87,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryLight,
      ),
    ),
    dividerColor: Colors.white12,
  );
}

