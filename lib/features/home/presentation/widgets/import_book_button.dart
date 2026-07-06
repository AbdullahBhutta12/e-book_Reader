import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';

/// A large, prominent call-to-action button used on the Home screen.
///
/// WHY THIS IS ITS OWN WIDGET (instead of an ElevatedButton written
/// directly inside home_screen.dart):
///   1. Single Responsibility — this widget's only job is to look like,
///      and behave as, the "Import Book" action. home_screen.dart stays
///      focused on layout, not button styling details.
///   2. Reusability — a future "empty library" screen can reuse this
///      exact button just by importing it, instead of copy-pasting code.
///   3. Testability — a small, focused widget is far easier to widget-test
///      in isolation than a giant screen.
class ImportBookButton extends StatelessWidget {
  const ImportBookButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  /// Callback fired when the user taps the button.
  ///
  /// This is passed IN from the parent (home_screen.dart) rather than
  /// hard-coded here. This widget doesn't need to know WHAT happens on
  /// tap — only that something does. This "callback pattern" is central
  /// to how Flutter widgets stay decoupled and reusable: the button
  /// doesn't care if it's opening a file picker or showing a dialog.
  final VoidCallback onPressed;

  /// Whether an import is currently in progress.
  ///
  /// NOTE: this widget still has NO business logic of its own — it
  /// doesn't know *why* it's loading, or call file_picker itself. It just
  /// renders differently based on a flag its parent hands it. The parent
  /// (`HomeScreen`) owns the actual state; this widget stays "dumb" and
  /// purely presentational, which is what keeps it easy to test and
  /// reuse.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // SizedBox forces the button to a fixed height and full available
    // width, which is what makes it look "large and professional"
    // instead of shrink-wrapping tightly around its label text.
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton.icon(
        // Passing `null` to onPressed is Flutter's built-in way to
        // disable a button — no separate "enabled" flag needed. While
        // loading, this prevents the user from firing a second file-pick
        // request on top of one that's already running.
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.file_upload_outlined, size: 24),
        label: Text(
          isLoading ? 'Importing…' : AppStrings.importButtonLabel,
        ),
      ),
    );
  }
}
