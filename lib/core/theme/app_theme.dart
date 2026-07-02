import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// Builds the single `ThemeData` object used across the whole app via
/// `MaterialApp(theme: AppTheme.light)`.
///
/// WHY CENTRALIZE THE THEME:
/// Instead of styling every AppBar, every button, every text widget
/// individually on every screen, we configure it ONCE here. Every widget
/// in the app then automatically inherits these styles unless explicitly
/// overridden. This is what makes an app feel consistent instead of like
/// a patchwork of differently-styled screens — and it means a future
/// rebrand is a one-file change.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,

      // ColorScheme.fromSeed generates a full, harmonious Material 3
      // color palette (primary, secondary, error, surface tones, etc.)
      // from just one seed color. This saves us from manually picking
      // a dozen shades that need to work well together.
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0, // Flat app bar — modern, no drop shadow.
        centerTitle: false,
        titleTextStyle: AppTextStyles.appBarTitle,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),

      textTheme: TextTheme(
        headlineMedium: AppTextStyles.heading,
        bodyMedium: AppTextStyles.subheading,
      ),
    );
  }
}
