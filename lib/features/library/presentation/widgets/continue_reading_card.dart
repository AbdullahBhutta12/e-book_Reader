import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/library_book.dart';

/// The featured card at the top of a populated library, for whichever
/// book `LibraryController.continueReadingBook` currently returns.
///
/// Purely presentational — same "dumb widget" shape as
/// `ImportBookButton`/`PlaybackControlBar`: it renders exactly what it's
/// handed and forwards a tap to a callback, with zero knowledge of how
/// `continueReadingBook` was chosen or what `onTap` will actually do.
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    required this.book,
    required this.progressFraction,
    required this.onTap,
  });

  final LibraryBook book;
  final double progressFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.continueReadingLabel,
                style: AppTextStyles.subheading.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.name,
                style: AppTextStyles.heading.copyWith(fontSize: 20),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 6,
                  backgroundColor: AppColors.surface,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(progressFraction * 100).round()}%',
                style: AppTextStyles.subheading.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
