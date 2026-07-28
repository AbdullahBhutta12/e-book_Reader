import 'package:flutter/foundation.dart';
import '../../../reader/data/reading_progress_store.dart';
import '../../../reader/domain/models/book_file.dart';
import '../../data/book_storage_service.dart';
import '../../data/library_store.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/library_sort_order.dart';

/// Owns the persistent library: which books exist, search and sort
/// state, importing a freshly-picked file (with duplicate detection),
/// and atomic deletion.
///
/// ARCHITECTURE NOTE — this is the library feature's counterpart to the
/// reader feature's `BookReaderController`, and deliberately mirrors its
/// shape:
///   Presentation (HomeScreen / book tiles / Continue Reading card)
///         ↓ calls importBook() / deleteBook() / setSearchQuery() / etc.
///   LibraryController            ← YOU ARE HERE
///         ↓ calls LibraryStore, BookStorageService, ReadingProgressStore
///   LibraryStore    BookStorageService    ReadingProgressStore
///         ↓                 ↓                     ↓
///   shared_preferences  path_provider      shared_preferences
/// Presentation never touches any of the three data-layer classes
/// directly — only this controller's methods and exposed getters.
///
/// WHY THIS DEPENDS ON `ReadingProgressStore` (a `reader`-feature class)
/// RATHER THAN DUPLICATING PROGRESS TRACKING: a `LibraryBook` never
/// stores a progress fraction itself — seeing "how far into this book"
/// requires asking the SAME store `BookReaderController` already writes
/// to, keyed by the SAME `identityKey`. Storing progress a second time,
/// here, would create two mutable copies of the same fact that could
/// drift out of sync — the exact failure mode `BookFile.format`
/// (replacing a raw extension string) was fixed to prevent, back in the
/// stability patch.
class LibraryController extends ChangeNotifier {
  LibraryController({
    LibraryStore? libraryStore,
    BookStorageService? storageService,
    ReadingProgressStore? progressStore,
  })  : _libraryStore = libraryStore ?? LibraryStore(),
        _storageService = storageService ?? const BookStorageService(),
        _progressStore = progressStore ?? ReadingProgressStore() {
    _loadLibrary();
  }

  /// Injected via the constructor with a sensible default — the same
  /// dependency-injection pattern used throughout this app since Module
  /// 2, for the same reason: a test can supply fakes for all three
  /// without touching real device storage or the file system.
  final LibraryStore _libraryStore;
  final BookStorageService _storageService;
  final ReadingProgressStore _progressStore;

  bool _disposed = false;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<LibraryBook> _books = const [];

  /// Whether the library has ANY books at all — deliberately distinct
  /// from `visibleBooks.isEmpty`, which can also be true just because a
  /// search query filtered every book out. `HomeScreen` uses this one to
  /// decide between the first-time "no books yet" empty state and the
  /// populated library layout (which has its own, separate "no results"
  /// message for an over-narrow search).
  bool get isEmpty => _books.isEmpty;

  /// Cached progress fraction per book, keyed by `identityKey` — loaded
  /// alongside the library itself, and refreshed via [refreshProgress]
  /// after returning from a reading session (see that method's own doc
  /// comment for why a manual refresh is needed at all).
  final Map<String, double> _progressFractions = {};

  /// `identityKey`s whose durable file could not be found on disk the
  /// last time the library loaded — see [isFileMissing].
  final Set<String> _missingFileIdentityKeys = {};

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  LibrarySortOrder _sortOrder = LibrarySortOrder.recentlyOpened;
  LibrarySortOrder get sortOrder => _sortOrder;

  /// The filtered (by [searchQuery]) and sorted (by [sortOrder]) list the
  /// library screen actually renders.
  ///
  /// WHY THIS IS COMPUTED ON DEMAND, NOT CACHED: the underlying list is
  /// small (see `LibraryStore`'s own doc comment on why that's a
  /// deliberate scale assumption, not an oversight), so recomputing a
  /// filter+sort over it is cheap. Caching a second, derived list here
  /// would mean a second copy of "the books" that could fall out of sync
  /// with `_books` — the single source of truth stays exactly that.
  List<LibraryBook> get visibleBooks {
    Iterable<LibraryBook> result = _books;

    if (_searchQuery.trim().isNotEmpty) {
      final String query = _searchQuery.trim().toLowerCase();
      result =
          result.where((book) => book.name.toLowerCase().contains(query));
    }

    final List<LibraryBook> list = result.toList();
    switch (_sortOrder) {
      case LibrarySortOrder.recentlyOpened:
        list.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      case LibrarySortOrder.title:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case LibrarySortOrder.recentlyImported:
        list.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    }
    return list;
  }

  /// The single most-recently-opened book with unfinished progress — the
  /// Continue Reading card's source, or `null` when there's nothing to
  /// feature (an empty library, or every book either never opened or
  /// already finished). Deliberately ignores [searchQuery]/[sortOrder] —
  /// the Continue Reading card is a fixed, separate piece of the screen,
  /// not part of the filtered/sorted list below it.
  LibraryBook? get continueReadingBook {
    final Iterable<LibraryBook> withProgress = _books.where(
      (book) => (_progressFractions[book.identityKey] ?? 0) > 0,
    );
    if (withProgress.isEmpty) return null;

    return withProgress.reduce(
      (a, b) => a.lastOpenedAt.isAfter(b.lastOpenedAt) ? a : b,
    );
  }

  /// How far into [book] the user has read, as a `0.0`–`1.0` fraction —
  /// `0` if this book has never been opened, or has no saved progress
  /// for any other reason.
  double progressFractionFor(LibraryBook book) =>
      _progressFractions[book.identityKey] ?? 0;

  /// `true` if this book's durable copy couldn't be found on disk the
  /// last time the library loaded (see `_loadLibrary`'s existence check).
  /// The UI uses this to show a quiet "unavailable" indicator on a tile
  /// rather than letting the user tap into a book that's guaranteed to
  /// fail to open — deletion (which already tolerates an already-missing
  /// file) remains the way to clean up an entry in this state.
  bool isFileMissing(LibraryBook book) =>
      _missingFileIdentityKeys.contains(book.identityKey);

  void setSearchQuery(String query) {
    if (_searchQuery == query) return; // avoid a no-op rebuild
    _searchQuery = query;
    _notify();
  }

  void setSortOrder(LibrarySortOrder order) {
    if (_sortOrder == order) return; // avoid a no-op rebuild
    _sortOrder = order;
    _notify();
  }

  /// Imports a freshly-picked file into the durable library. This is
  /// `HomeScreen`'s "Import Book" button's counterpart to
  /// `BookImportService.pickBook()` — that method validates and returns
  /// a `BookFile` pointing at `file_picker`'s transient path; THIS method
  /// is what turns that into a permanent library entry.
  ///
  /// DUPLICATE DETECTION: if a book with the same `identityKey` is
  /// already in the library, this returns THAT existing entry (with
  /// [recordOpened] applied) instead of copying the file a second time —
  /// the actual mechanism behind "the app should remember imported books
  /// so users don't have to import the same book repeatedly."
  Future<LibraryBook> importBook(BookFile pickedFile) async {
    final int existingIndex = _books.indexWhere(
      (book) => book.identityKey == pickedFile.identityKey,
    );
    if (existingIndex != -1) {
      // Re-importing a book already in the library — it's clearly
      // available again (the user just picked it), so any stale
      // "missing" flag no longer applies.
      _missingFileIdentityKeys.remove(pickedFile.identityKey);
      return recordOpened(_books[existingIndex]);
    }

    final String storedPath = await _storageService.store(pickedFile);
    final DateTime now = DateTime.now();
    final LibraryBook newBook = LibraryBook(
      identityKey: pickedFile.identityKey,
      name: pickedFile.name,
      format: pickedFile.format,
      sizeInBytes: pickedFile.sizeInBytes,
      storedPath: storedPath,
      importedAt: now,
      lastOpenedAt: now,
    );

    _books = [..._books, newBook];
    await _libraryStore.saveAll(_books);
    _notify();
    return newBook;
  }

  /// Refreshes [book]'s `lastOpenedAt` to now — called both by
  /// [importBook] (when it resolves to an already-existing entry) and
  /// directly by the UI when the user taps an existing library tile to
  /// reopen it.
  Future<LibraryBook> recordOpened(LibraryBook book) async {
    final LibraryBook updated = book.copyWith(lastOpenedAt: DateTime.now());
    _books = [
      for (final LibraryBook existing in _books)
        if (existing.identityKey == book.identityKey) updated else existing,
    ];
    await _libraryStore.saveAll(_books);
    _notify();
    return updated;
  }

  /// Removes [book] from the library — ATOMICALLY, in the sense that all
  /// three places a book's existence is recorded are cleaned up
  /// together: the library entry itself, its durable file copy, and any
  /// saved reading progress. A partial deletion (e.g. the file removed
  /// but the library entry lingering, or vice versa) would be a worse
  /// bug than the one a "Delete" button exists to let the user fix.
  ///
  /// SAFE TO CALL EVEN WHEN [isFileMissing] IS ALREADY TRUE:
  /// `BookStorageService.delete` only deletes a file that still exists,
  /// so cleaning up a library entry whose file is already gone (the
  /// exact case this method exists to let the user resolve) never
  /// throws over the file already being absent.
  ///
  /// WHY THE IN-MEMORY LIST AND `LibraryStore` UPDATE FIRST, BEFORE THE
  /// FILE AND PROGRESS CLEANUP: the book disappearing from the UI is the
  /// user-visible confirmation that delete "worked" — that should happen
  /// immediately, not after two more slower disk operations complete.
  Future<void> deleteBook(LibraryBook book) async {
    _books = _books
        .where((existing) => existing.identityKey != book.identityKey)
        .toList();
    _progressFractions.remove(book.identityKey);
    _missingFileIdentityKeys.remove(book.identityKey);
    _notify();

    await _libraryStore.saveAll(_books);
    await _storageService.delete(book.storedPath);
    await _progressStore.clear(book.identityKey);
  }

  /// Re-reads every book's progress from `ReadingProgressStore`.
  ///
  /// WHY THIS NEEDS TO BE CALLED EXPLICITLY (it isn't automatic): this
  /// controller has no way to know a reading session happened elsewhere
  /// in the app and changed a book's saved progress — `HomeScreen` calls
  /// this itself right after a `Navigator.push` to `ReaderScreen`
  /// returns, which is the natural "the user might have just changed
  /// something" moment.
  Future<void> refreshProgress() async {
    for (final LibraryBook book in _books) {
      final progress = await _progressStore.load(book.identityKey);
      if (progress != null) {
        _progressFractions[book.identityKey] = progress.fraction;
      } else {
        // BUG FIX: previously left a stale cached fraction in place when
        // progress had been cleared elsewhere (a finished book — see
        // `BookReaderController._handleChunkCompletion` — or a book
        // whose progress this controller's own `deleteBook` just
        // cleared). That meant a finished book could keep incorrectly
        // appearing as `continueReadingBook` until the app restarted.
        // Removing the stale entry here is what makes "no progress" and
        // "never had progress" behave identically, as they should.
        _progressFractions.remove(book.identityKey);
      }
    }
    _notify();
  }

  /// Loads the library, then checks each book's durable file still
  /// exists on disk — never crashes over a book whose file is missing or
  /// corrupted: `BookStorageService.exists` is a plain boolean check (see
  /// its own doc comment), and a book found missing is simply flagged
  /// via [isFileMissing] rather than removed or allowed to throw.
  Future<void> _loadLibrary() async {
    _books = await _libraryStore.loadAll();

    for (final LibraryBook book in _books) {
      final bool exists = await _storageService.exists(book.storedPath);
      if (!exists) {
        _missingFileIdentityKeys.add(book.identityKey);
      }
    }

    await refreshProgress(); // also calls _notify()
    _isLoading = false;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
