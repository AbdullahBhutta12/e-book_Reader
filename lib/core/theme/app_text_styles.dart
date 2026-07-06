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

  /// Body text for the actual book-reading view.
  ///
  /// WHY A SEPARATE STYLE (AND A SEPARATE TYPEFACE) FROM THE REST OF THE
  /// APP: `heading`/`subheading`/`button` above are UI chrome — buttons,
  /// titles, labels — where a clean sans-serif (Poppins/Inter) looks
  /// modern. Long-form reading is a different job: serif typefaces with
  /// generous line height (`height: 1.6` here, vs. `1.3`–`1.5` for UI
  /// text) are consistently easier to read for extended passages of text
  /// — this is why e-readers and reading apps almost universally use a
  /// serif body font even when their surrounding UI doesn't. "Lora" is a
  /// Google Fonts serif designed specifically for on-screen body text.
  static TextStyle get readingBody => GoogleFonts.lora(
        fontSize: 17,
        height: 1.6,
        color: AppColors.textPrimary,
      );
}
