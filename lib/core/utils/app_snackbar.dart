import 'package:flutter/material.dart';

/// Shared helper for showing SnackBars consistently across the app.
///
/// WHY THIS EXISTS:
/// Module 1's `HomeScreen` had `ScaffoldMessenger.of(context).showSnackBar`
/// boilerplate written directly inside it. Module 2 needs to show
/// SnackBars too (for import errors) — copy-pasting that boilerplate a
/// second time would violate the "no duplicate code" rule and mean two
/// places to keep visually consistent by hand. Centralizing it here means
/// every SnackBar in the app looks and behaves the same, and there's
/// exactly one place to change that later.
class AppSnackbar {
  AppSnackbar._();

  /// A neutral, informational message (e.g. "Coming soon").
  static void showInfo(BuildContext context, String message) {
    _show(context, message, backgroundColor: null);
  }

  /// An error message — visually distinct (red-tinted) so it reads as a
  /// problem, not routine feedback.
  static void showError(BuildContext context, String message) {
    _show(context, message, backgroundColor: Colors.red.shade700);
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color? backgroundColor,
  }) {
    ScaffoldMessenger.of(context)
      // Clears any SnackBar currently showing first. Without this, rapid
      // taps (e.g. tapping Import twice quickly) can queue up multiple
      // SnackBars that appear one after another instead of just showing
      // the latest, most relevant message.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
        ),
      );
  }
}
