import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../library/domain/models/library_book.dart';
import '../../../library/domain/models/library_sort_order.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/widgets/continue_reading_card.dart';
import '../../../library/presentation/widgets/library_book_tile.dart';
import '../../../reader/data/book_import_service.dart';
import '../../../reader/domain/models/book_file.dart';
import '../../../reader/domain/models/book_import_result.dart';
import '../../../reader/presentation/screens/reader_screen.dart';
import '../widgets/import_book_button.dart';

/// The first screen the user sees when opening the app.
///
/// MODULE 8: this is now a library-first screen, not just a single
/// "Import Book" action — the actual point of a persistent library is
/// that most visits start here with books already in it, not with
/// picking a file. `ImportBookButton`/the empty-state layout from
/// Module 1 are preserved verbatim for first-time users who have no
/// library yet; everything else here is new.
///
/// WHY THIS WRAPS A `ChangeNotifierProvider<LibraryController>` — the
/// exact same pattern `ReaderScreen` uses for `BookReaderController`:
/// the library needs to be shared across everything on this screen (the
/// Continue Reading card, search, sort, every book tile) without
/// threading it through each of their constructors by hand.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, BookImportService? importService})
      : _importService = importService ?? const BookImportService();

  /// Same DI-with-a-default pattern used throughout this app since
  /// Module 2 — a test can supply a fake without touching a real device
  /// file picker.
  final BookImportService _importService;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LibraryController(),
      child: _HomeView(importService: _importService),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({required this.importService});

  final BookImportService importService;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  /// Whether an import is currently in progress — the only mutable state
  /// this screen itself owns (everything else lives in
  /// `LibraryController`). Exists for exactly one reason: telling
  /// `ImportBookButton` whether to show its spinner.
  bool _isImporting = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleImportPressed() async {
    setState(() => _isImporting = true);

    // Same defense-in-depth try/catch as Module 2/the stability patch —
    // BookImportService.pickBook() already guarantees it never throws,
    // but this screen's own promise (the button never gets stuck
    // spinning) shouldn't depend on trusting an injected dependency.
    BookImportResult result;
    try {
      result = await widget.importService.pickBook();
    } catch (_) {
      result = const BookImportFailure(AppStrings.importGenericError);
    }

    if (!mounted) return;
    setState(() => _isImporting = false);

    switch (result) {
      case BookImportSuccess(:final book):
        await _importAndOpen(book);
      case BookImportCancelled():
        break; // normal outcome, no feedback needed
      case BookImportUnsupportedFormat(:final extension):
        AppSnackbar.showError(
          context,
          AppStrings.unsupportedFormatMessage(extension),
        );
      case BookImportFailure(:final message):
        AppSnackbar.showError(context, message);
    }
  }

  /// Hands a freshly-picked file to `LibraryController.importBook` (which
  /// copies it into durable storage, or recognizes it as already in the
  /// library — see that method's own doc comment for the duplicate-
  /// detection logic), then opens the resulting `LibraryBook`.
  Future<void> _importAndOpen(BookFile pickedFile) async {
    final controller = context.read<LibraryController>();
    final LibraryBook libraryBook = await controller.importBook(pickedFile);
    if (!mounted) return;
    await _openLibraryBook(libraryBook);
  }

  /// Opens [book] in the Reader — ALWAYS via `book.toBookFile()`, which
  /// points at this app's own durable copy (`LibraryBook.storedPath`),
  /// never at wherever the original pick came from. This is the concrete
  /// place "imported books keep working even if the original source file
  /// is deleted or moved" is actually true: from here on, nothing about
  /// reading this book ever looks at the original file again.
  Future<void> _openLibraryBook(LibraryBook book) async {
    final controller = context.read<LibraryController>();
    await controller.recordOpened(book);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(book: book.toBookFile()),
      ),
    );

    // MODULE 8: `LibraryController`'s cached progress fractions were
    // loaded before this reading session happened — there is no
    // automatic way for it to know progress changed elsewhere in the
    // app, so refreshing here, the moment we're back, is what keeps the
    // Continue Reading card and this book's progress bar accurate.
    if (!mounted) return;
    await context.read<LibraryController>().refreshProgress();
  }

  Future<void> _handleDeleteBook(LibraryBook book) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.deleteBookDialogTitle),
        content: const Text(AppStrings.deleteBookDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.deleteButtonLabel),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<LibraryController>().deleteBook(book);
  }

  @override
  Widget build(BuildContext context) {
    // Deciding empty-vs-populated layout is the one thing worth a
    // `context.watch` at this top level — everything BELOW that
    // decision uses `context.select` for its own narrower slice, same
    // rebuild-scoping discipline `ReaderScreen` established.
    final bool isLoading =
        context.select<LibraryController, bool>((c) => c.isLoading);
    final bool isEmpty =
        context.select<LibraryController, bool>((c) => c.isEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.homeTitle)),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : isEmpty
                ? _EmptyLibraryState(
                    isImporting: _isImporting,
                    onImportPressed: _handleImportPressed,
                  )
                : _PopulatedLibrary(
                    searchController: _searchController,
                    onOpenBook: _openLibraryBook,
                    onDeleteBook: _handleDeleteBook,
                  ),
      ),
      floatingActionButton: isLoading || isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isImporting ? null : _handleImportPressed,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(
                _isImporting ? 'Importing…' : AppStrings.importButtonLabel,
              ),
            ),
    );
  }
}

/// Module 1's original first-time layout, preserved verbatim: welcome
/// illustration, heading, subtitle, and one large, centered Import
/// button — shown only while the library has no books at all.
class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({
    required this.isImporting,
    required this.onImportPressed,
  });

  final bool isImporting;
  final VoidCallback onImportPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const _WelcomeIllustration(),
          const Spacer(),
          Text(AppStrings.welcomeHeading, style: AppTextStyles.heading),
          const SizedBox(height: 12),
          Text(AppStrings.welcomeSubtitle, style: AppTextStyles.subheading),
          const SizedBox(height: 32),
          ImportBookButton(
            isLoading: isImporting,
            onPressed: onImportPressed,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.auto_stories_outlined,
          size: 84,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// The Module 8 layout: Continue Reading card (if applicable), a search
/// field, a sort control, and the filtered/sorted book list.
class _PopulatedLibrary extends StatelessWidget {
  const _PopulatedLibrary({
    required this.searchController,
    required this.onOpenBook,
    required this.onDeleteBook,
  });

  final TextEditingController searchController;
  final ValueChanged<LibraryBook> onOpenBook;
  final ValueChanged<LibraryBook> onDeleteBook;

  @override
  Widget build(BuildContext context) {
    final LibraryBook? continueReading =
        context.select<LibraryController, LibraryBook?>(
      (c) => c.continueReadingBook,
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (continueReading != null) ...[
                  _ContinueReadingSection(
                    book: continueReading,
                    onTap: () => onOpenBook(continueReading),
                  ),
                  const SizedBox(height: 20),
                ],
                _SearchField(controller: searchController),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStrings.libraryTitle,
                      style: AppTextStyles.heading.copyWith(fontSize: 18),
                    ),
                    const _SortRow(),
                  ],
                ),
              ],
            ),
          ),
        ),
        _LibraryBookList(onOpenBook: onOpenBook, onDeleteBook: onDeleteBook),
      ],
    );
  }
}

/// Isolated so only this small subtree rebuilds when
/// `continueReadingBook`'s own progress fraction changes — not the whole
/// populated-library layout around it.
class _ContinueReadingSection extends StatelessWidget {
  const _ContinueReadingSection({required this.book, required this.onTap});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double fraction = context.select<LibraryController, double>(
      (c) => c.progressFractionFor(book),
    );
    return ContinueReadingCard(
      book: book,
      progressFraction: fraction,
      onTap: onTap,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: context.read<LibraryController>().setSearchQuery,
      decoration: InputDecoration(
        hintText: AppStrings.librarySearchHint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow();

  static const Map<LibrarySortOrder, String> _labels = {
    LibrarySortOrder.recentlyOpened: AppStrings.sortByRecentlyOpened,
    LibrarySortOrder.title: AppStrings.sortByTitle,
    LibrarySortOrder.recentlyImported: AppStrings.sortByRecentlyImported,
  };

  @override
  Widget build(BuildContext context) {
    final LibrarySortOrder current =
        context.select<LibraryController, LibrarySortOrder>(
      (c) => c.sortOrder,
    );

    return PopupMenuButton<LibrarySortOrder>(
      tooltip: AppStrings.sortButtonTooltip,
      initialValue: current,
      onSelected: context.read<LibraryController>().setSortOrder,
      itemBuilder: (context) => [
        for (final entry in _labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(_labels[current]!, style: AppTextStyles.subheading),
        ],
      ),
    );
  }
}

/// The actual scrollable book list — a `SliverList` (not a plain
/// `ListView`) so it composes correctly inside the `CustomScrollView`
/// above it, alongside the non-scrolling-independent header content.
class _LibraryBookList extends StatelessWidget {
  const _LibraryBookList({
    required this.onOpenBook,
    required this.onDeleteBook,
  });

  final ValueChanged<LibraryBook> onOpenBook;
  final ValueChanged<LibraryBook> onDeleteBook;

  @override
  Widget build(BuildContext context) {
    final List<LibraryBook> books =
        context.select<LibraryController, List<LibraryBook>>(
      (c) => c.visibleBooks,
    );

    if (books.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.only(top: 48),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: Text(
              AppStrings.libraryEmptySearchMessage,
              style: AppTextStyles.subheading,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      sliver: SliverList.separated(
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final LibraryBook book = books[index];
          return _LibraryTileWithState(
            book: book,
            onOpen: () => onOpenBook(book),
            onDelete: () => onDeleteBook(book),
          );
        },
      ),
    );
  }
}

/// Isolated per-tile so only ONE row rebuilds when ITS OWN progress
/// fraction or missing-file status changes — not the whole list.
class _LibraryTileWithState extends StatelessWidget {
  const _LibraryTileWithState({
    required this.book,
    required this.onOpen,
    required this.onDelete,
  });

  final LibraryBook book;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final double fraction = context.select<LibraryController, double>(
      (c) => c.progressFractionFor(book),
    );
    final bool missing = context.select<LibraryController, bool>(
      (c) => c.isFileMissing(book),
    );

    return LibraryBookTile(
      book: book,
      progressFraction: fraction,
      isFileMissing: missing,
      onTap: onOpen,
      onDelete: onDelete,
    );
  }
}
