import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// A single labeled row of book metadata — an icon, a label, and a value.
///
/// WHY A REUSABLE WIDGET (instead of writing this Row four times inline
/// in `reader_screen.dart` — once each for name, size, path, extension):
/// The rule "no duplicate code" applies just as much to UI as to business
/// logic. Four near-identical `Row(...)` blocks copy-pasted with only the
/// label/value changed is exactly the kind of duplication that makes a
/// codebase painful to maintain — change the label's font size once, and
/// you'd need to change it in four places instead of one.
class BookDetailTile extends StatelessWidget {
  const BookDetailTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          // Expanded lets the text column take up all remaining width and
          // wrap naturally — important here since file paths can be long
          // and would otherwise overflow off the right edge of the screen.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.subheading.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
