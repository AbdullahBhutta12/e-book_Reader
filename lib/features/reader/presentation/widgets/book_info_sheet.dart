import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/book_file.dart';
import 'book_detail_tile.dart';

/// The file metadata view from Module 2 (name, size, path, extension) —
/// now shown as an on-demand bottom sheet instead of being the entire
/// Reader screen.
///
/// WHY THIS MOVED FROM "the whole screen" TO "a sheet you open":
/// Module 2's job WAS showing file metadata — that's all the Reader
/// screen had to display yet. Now that Module 3 actually displays the
/// book's content, that content is rightfully the main event, and file
/// metadata becomes secondary reference information — useful, but not
/// something that should push the actual reading experience below the
/// fold. Nothing about this data or its layout changed; only where it's
/// shown did.
///
/// Call this via [show] rather than constructing it directly — that
/// keeps the `showModalBottomSheet` boilerplate in one place instead of
/// wherever this sheet gets triggered from.
class BookInfoSheet extends StatelessWidget {
  const BookInfoSheet({super.key, required this.book});

  final BookFile book;

  static Future<void> show(BuildContext context, BookFile book) {
    return showModalBottomSheet<void>(
      context: context,
      // Lets the sheet's content decide its own height (via
      // SingleChildScrollView + Wrap below) instead of being locked to
      // roughly half the screen, which is the default.
      isScrollControlled: true,
      builder: (_) => BookInfoSheet(book: book),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        // SingleChildScrollView protects us the same way it did in
        // Module 2's ReaderScreen: a long file path, on a small phone,
        // could need more vertical space than is available — this lets
        // the sheet scroll instead of overflowing.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A small drag-handle bar — the standard visual cue that
              // this is a modal sheet, not a full page.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                AppStrings.bookInfoSheetTitle,
                style: AppTextStyles.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 20),
              BookDetailTile(
                icon: Icons.insert_drive_file_outlined,
                label: AppStrings.labelFileName,
                value: book.name,
              ),
              const SizedBox(height: 12),
              BookDetailTile(
                icon: Icons.memory_outlined,
                label: AppStrings.labelFileSize,
                value: book.formattedSize,
              ),
              const SizedBox(height: 12),
              BookDetailTile(
                icon: Icons.folder_open_outlined,
                label: AppStrings.labelFilePath,
                value: book.path,
              ),
              const SizedBox(height: 12),
              BookDetailTile(
                icon: Icons.info_outlined,
                label: AppStrings.labelFileExtension,
                value: book.extension.toUpperCase(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
