import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/library_book.dart';

/// One row in the library's book list — same "dumb widget" shape as
/// `ContinueReadingCard`: renders exactly what it's handed, forwards taps
/// to callbacks, and has no idea how any of those values were computed
/// or what tapping them will actually do.
class LibraryBookTile extends StatelessWidget {
  const LibraryBookTile({
    super.key,
    required this.book,
    required this.progressFraction,
    required this.isFileMissing,
    required this.onTap,
    required this.onDelete,
  });

  final LibraryBook book;
  final double progressFraction;

  /// `true` when `LibraryController.isFileMissing(book)` — this book's
  /// durable copy couldn't be found on disk. The tile still renders (the
  /// user needs a way to see and remove it), but visually distinguishes
  /// it and skips the progress bar, which has nothing meaningful to show
  /// for a book that can't currently be opened.
  final bool isFileMissing;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isFileMissing ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFileMissing
                      ? AppColors.border
                      : AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFileMissing
                      ? Icons.error_outline
                      : Icons.insert_drive_file_outlined,
                  color: isFileMissing
                      ? AppColors.textSecondary
                      : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.name,
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isFileMissing
                          ? AppStrings.libraryFileMissingLabel
                          : '${book.format.extension.toUpperCase()} · ${book.formattedSize}',
                      style: AppTextStyles.subheading.copyWith(fontSize: 12),
                    ),
                    if (!isFileMissing && progressFraction > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progressFraction,
                          minHeight: 4,
                          backgroundColor: AppColors.border,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: AppStrings.deleteBookButtonTooltip,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.textSecondary,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
