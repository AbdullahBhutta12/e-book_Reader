import 'package:flutter/material.dart';

/// Centralized color palette for the entire app.
///
/// WHY THIS FILE EXISTS:
/// Hard-coding colors like `Color(0xFF4F46E5)` inside individual widgets
/// makes an app painful to maintain — if the brand color changes, you'd
/// have to hunt through every screen to update it. Defining colors ONCE
/// here gives us:
///   1. A single source of truth for the brand palette.
///   2. Self-documenting names (`AppColors.primary` instead of a hex code).
///   3. An easy place to add a dark-mode palette later.
class AppColors {
  // Private constructor. This class only holds static constants — nobody
  // should ever write `AppColors()`. The underscore makes the constructor
  // private to this file, so Dart blocks that from anywhere else.
  AppColors._();

  /// Main brand color — buttons, active icons, highlighted text (later).
  static const Color primary = Color(0xFF4F46E5); // Indigo 600

  /// A pale tint of primary, used for soft backgrounds behind icons.
  static const Color primaryLight = Color(0xFFEEF0FF);

  /// App background — soft off-white, gentler on the eyes than pure white.
  static const Color background = Color(0xFFF8F9FC);

  /// Card / surface color.
  static const Color surface = Color(0xFFFFFFFF);

  /// Primary text — a near-black, not pure black (softer, more modern).
  static const Color textPrimary = Color(0xFF1A1B25);

  /// Secondary text — subtitles, hints, helper copy.
  static const Color textSecondary = Color(0xFF6B7280);

  /// Border / divider color.
  static const Color border = Color(0xFFE5E7EB);
}
