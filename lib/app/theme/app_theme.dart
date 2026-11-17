import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  // Legacy colors (backward compatibility)
  static const Color primaryBlue = Color(0xFF2E49A0);
  static const Color primaryGold = Color(0xFFD2A645);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryNavy,
        primary: AppColors.primaryNavy,
        secondary: AppColors.premiumGold,
        surface: AppColors.surface,
        error: AppColors.error,
        brightness: Brightness.light,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accentBlue,
        unselectedLabelColor: Colors.white,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.focused)) {
            return Colors.white.withValues(alpha: 0.24);
          }
          return null;
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        color: AppColors.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: AppColors.secondaryText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryNavy,
          side: const BorderSide(color: AppColors.primaryNavy),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryNavy,
        labelStyle: const TextStyle(color: AppColors.primaryText),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: AppColors.surface,
      ),
      fontFamily: null,
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.primaryText),
        displayMedium: TextStyle(color: AppColors.primaryText),
        displaySmall: TextStyle(color: AppColors.primaryText),
        headlineLarge: TextStyle(color: AppColors.primaryText),
        headlineMedium: TextStyle(color: AppColors.primaryText),
        headlineSmall: TextStyle(color: AppColors.primaryText),
        titleLarge: TextStyle(color: AppColors.primaryText),
        titleMedium: TextStyle(color: AppColors.primaryText),
        titleSmall: TextStyle(color: AppColors.primaryText),
        bodyLarge: TextStyle(color: AppColors.primaryText),
        bodyMedium: TextStyle(color: AppColors.secondaryText),
        bodySmall: TextStyle(color: AppColors.secondaryText),
        labelLarge: TextStyle(color: AppColors.primaryText),
        labelMedium: TextStyle(color: AppColors.secondaryText),
        labelSmall: TextStyle(color: AppColors.secondaryText),
      ),
    );
  }
}
