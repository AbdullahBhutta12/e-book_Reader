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
  });

  /// Callback fired when the user taps the button.
  ///
  /// This is passed IN from the parent (home_screen.dart) rather than
  /// hard-coded here. This widget doesn't need to know WHAT happens on
  /// tap — only that something does. This "callback pattern" is central
  /// to how Flutter widgets stay decoupled and reusable: the button
  /// doesn't care if it's opening a file picker, showing a dialog, or (as
  /// in this module) just a SnackBar.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // SizedBox forces the button to a fixed height and full available
    // width, which is what makes it look "large and professional"
    // instead of shrink-wrapping tightly around its label text.
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.file_upload_outlined, size: 24),
        label: const Text(AppStrings.importButtonLabel),
      ),
    );
  }
}
