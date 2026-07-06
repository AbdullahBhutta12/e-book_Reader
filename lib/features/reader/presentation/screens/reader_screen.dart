import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/book_content_result.dart';
import '../../domain/models/book_file.dart';
import '../controllers/book_reader_controller.dart';
import '../widgets/book_content_view.dart';
import '../widgets/book_info_sheet.dart';

/// Shown after a book has been successfully imported and validated.
///
/// Module 2's version of this screen only displayed file metadata.
/// Module 3 adds the real thing: extracting and displaying the book's
/// actual text, using the `TextExtractor` abstraction the architecture
/// review set up specifically for this step.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.book});

  final BookFile book;

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider is created HERE, scoped to this screen —
    // not at the app's root. It's built once when ReaderScreen is pushed
    // and automatically disposed (its `dispose()` called, listeners
    // cleaned up) when the screen is popped. `provider` package rule of
    // thumb: create a provider as close as possible to where it's
    // actually needed, not higher up "just in case."
    return ChangeNotifierProvider(
      create: (_) => BookReaderController(book: book),
      child: const _ReaderView(),
    );
  }
}

/// Everything below this point reads `BookReaderController` via
/// `provider` instead of taking `book` as a constructor parameter — this
/// is what lets the AppBar, the info button, and the body all react to
/// the SAME controller without it being threaded through each of their
/// constructors by hand.
class _ReaderView extends StatelessWidget {
  const _ReaderView();

  @override
  Widget build(BuildContext context) {
    // context.watch subscribes this widget to the controller: whenever
    // `notifyListeners()` is called inside BookReaderController, this
    // build method runs again automatically. This is the whole reason
    // BookReaderController extends ChangeNotifier instead of being a
    // plain class.
    final controller = context.watch<BookReaderController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          controller.book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: AppStrings.bookInfoButtonTooltip,
            icon: const Icon(Icons.info_outline),
            onPressed: () => BookInfoSheet.show(context, controller.book),
          ),
        ],
      ),
      body: SafeArea(child: _ReaderBody(result: controller.result)),
    );
  }
}

/// Picks which state to render based on the controller's current result.
///
/// Same Dart 3 exhaustive-switch pattern used for `BookImportResult` in
/// Module 2 — `result` can be `null` (still loading) or one of
/// `BookContentResult`'s three subtypes, and every case is handled
/// explicitly.
class _ReaderBody extends StatelessWidget {
  const _ReaderBody({required this.result});

  final BookContentResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;

    if (result == null) {
      return const _LoadingState();
    }

    return switch (result) {
      BookContentLoaded(:final content) => content.paragraphs.isEmpty
          ? const _EmptyBookState()
          : BookContentView(content: content),
      BookContentUnsupportedFormat(:final extension) =>
        _UnsupportedFormatState(extension: extension),
      BookContentLoadFailure(:final message) =>
        _LoadFailureState(message: message),
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            AppStrings.readerLoadingMessage,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyBookState extends StatelessWidget {
  const _EmptyBookState();

  @override
  Widget build(BuildContext context) {
    return const _StatusMessage(
      icon: Icons.insert_drive_file_outlined,
      title: AppStrings.readerEmptyBookTitle,
      message: AppStrings.readerEmptyBookMessage,
    );
  }
}

class _UnsupportedFormatState extends StatelessWidget {
  const _UnsupportedFormatState({required this.extension});

  final String extension;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: Icons.hourglass_empty_outlined,
      title: AppStrings.readerUnsupportedFormatTitle,
      message: AppStrings.readerUnsupportedFormatBody(extension),
    );
  }
}

class _LoadFailureState extends StatelessWidget {
  const _LoadFailureState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: Icons.error_outline,
      title: AppStrings.readerLoadFailureTitle,
      message: message,
    );
  }
}

/// Shared layout for every "nothing to show, here's why" state above.
///
/// Extracted for the same reason `BookDetailTile` was in Module 2: three
/// near-identical "icon + title + message, centered" layouts is exactly
/// the kind of UI duplication the "no duplicate code" rule is about.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.heading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.subheading,
            ),
          ],
        ),
      ),
    );
  }
}
