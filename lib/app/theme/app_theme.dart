import 'package:flutter/material.dart';

class AppTheme {
  // لون ميزان العدالة الكحلي
  static const Color primaryBlue = Color(0xFF2E49A0);
  // لون الريشة الذهبي[cite: 2]
  static const Color primaryGold = Color(0xFFD2A645); 

  static ThemeData get lightTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: primaryGold,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
    );
  }
}