import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralized typography for the app.
///
/// WHY google_fonts:
/// Flutter ships only a generic system font by default. `google_fonts` is
/// one of the most popular, actively-maintained Flutter packages and lets
/// us use professional typefaces (here: "Poppins" for headings, "Inter"
/// for body text) WITHOUT manually downloading .ttf files and registering
/// them by hand in pubspec.yaml. It fetches and caches the font, which is
/// why it's an industry-standard choice for typography in Flutter apps.
class AppTextStyles {
  AppTextStyles._();

  /// Big, bold heading — used for the main welcome message.
  static TextStyle get heading => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  /// Softer, smaller text — used for descriptive/supporting copy.
  static TextStyle get subheading => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  /// Text style for buttons — bold and white so it reads clearly against
  /// the solid primary-color button background.
  static TextStyle get button => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.2,
      );

  /// Title shown in the AppBar.
  static TextStyle get appBarTitle => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );
}
