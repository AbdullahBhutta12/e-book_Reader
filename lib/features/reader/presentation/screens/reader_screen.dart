import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/book_file.dart';
import '../widgets/book_detail_tile.dart';

/// Shown after a book has been successfully imported and validated.
///
/// For now (Module 2), this screen only displays the file's metadata —
/// name, size, path, extension. Actually opening and rendering the book's
/// *content*, plus Text-to-Speech and highlighting, are later modules.
///
/// WHY StatelessWidget:
/// Same reasoning as `HomeScreen` in Module 1 — this screen just displays
/// data it's handed, and nothing on it changes while it's on screen. It
/// takes a `BookFile` up front and renders it; no internal state needed.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.book});

  /// The validated book to display. Passed in directly through the
  /// constructor rather than looked up some other way (like a global
  /// singleton) — this is called "constructor injection," and it means
  /// you can tell exactly what this screen depends on just by reading its
  /// constructor, and can easily give it a different `BookFile` in a
  /// widget test.
  final BookFile book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.readerScreenTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // SingleChildScrollView means this screen won't overflow and
          // throw a rendering error if the file path is long enough to
          // need more vertical space than one screen height — small
          // phones and long paths are exactly when this matters.
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookHeader(book: book),
              const SizedBox(height: 32),
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

/// Decorative header: a book icon plus the file name in large text.
///
/// Private to this file (leading `_`) for the same reason as Module 1's
/// `_WelcomeIllustration` — it's an implementation detail of this one
/// screen, not something any other screen needs to reuse.
class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.book});

  final BookFile book;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_stories_outlined,
            color: AppColors.primary,
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            book.name,
            style: AppTextStyles.heading.copyWith(fontSize: 22),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
