import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_reader/features/library/data/book_storage_service.dart';
import 'package:ebook_reader/features/library/data/library_store.dart';
import 'package:ebook_reader/features/library/domain/models/library_book.dart';
import 'package:ebook_reader/features/library/domain/models/library_sort_order.dart';
import 'package:ebook_reader/features/library/presentation/controllers/library_controller.dart';
import 'package:ebook_reader/features/reader/data/reading_progress_store.dart';
import 'package:ebook_reader/features/reader/domain/models/book_file.dart';
import 'package:ebook_reader/features/reader/domain/models/reading_progress.dart';
import 'package:ebook_reader/features/reader/domain/models/supported_book_format.dart';

/// In-memory fake — avoids ever touching real `shared_preferences`.
///
/// WHY SUBCLASSING (`extends LibraryStore`) RATHER THAN IMPLEMENTING AN
/// INTERFACE: `LibraryStore` is a deliberately concrete class (see its
/// own doc comment — one real implementation this app needs, same
/// reasoning as `TtsService`), so there's no abstract contract to
/// implement here. Overriding its two public methods on a subclass is
/// the natural test-double shape for a class designed this way.
class _FakeLibraryStore extends LibraryStore {
  List<LibraryBook> saved = [];
  int saveCallCount = 0;

  @override
  Future<List<LibraryBook>> loadAll() async => saved;

  @override
  Future<void> saveAll(List<LibraryBook> books) async {
    saved = books;
    saveCallCount++;
  }
}

/// In-memory fake — avoids ever touching `path_provider`/real disk I/O.
class _FakeBookStorageService extends BookStorageService {
  final List<String> storeCalls = [];
  final List<String> deleteCalls = [];

  /// Paths this fake should report as NOT existing when [exists] is
  /// called — everything else defaults to "exists".
  final Set<String> missingPaths = {};

  @override
  Future<String> store(BookFile source) async {
    storeCalls.add(source.identityKey);
    return '/fake/library_books/${source.identityKey}';
  }

  @override
  Future<void> delete(String storedPath) async {
    deleteCalls.add(storedPath);
  }

  @override
  Future<bool> exists(String storedPath) async =>
      !missingPaths.contains(storedPath);
}

/// In-memory fake — avoids ever touching real `shared_preferences`.
class _FakeReadingProgressStore extends ReadingProgressStore {
  final Map<String, ReadingProgress> saved = {};
  final List<String> clearCalls = [];

  @override
  Future<void> save(ReadingProgress progress) async {
    saved[progress.bookPath] = progress;
  }

  @override
  Future<ReadingProgress?> load(String bookPath) async => saved[bookPath];

  @override
  Future<void> clear(String bookPath) async {
    saved.remove(bookPath);
    clearCalls.add(bookPath);
  }
}

BookFile _fakePickedFile(String name, int sizeInBytes) => BookFile(
      name: name,
      path: '/fake/picked/$name',
      format: SupportedBookFormat.plainText,
      sizeInBytes: sizeInBytes,
    );

/// `LibraryController`'s constructor kicks off its initial load
/// (`_loadLibrary`) WITHOUT awaiting it — the same fire-and-forget
/// pattern `BookReaderController` uses for `_loadContent`/
/// `_initializeTts`. In the real app this is never a race: every path to
/// `importBook`/`deleteBook`/etc. is gated behind `HomeScreen` only
/// showing those actions once `isLoading` is false. Tests calling
/// controller methods directly (bypassing that UI gate) need to wait for
/// the same condition explicitly — this helper does exactly that.
Future<void> _waitForInitialLoad(LibraryController controller) async {
  while (controller.isLoading) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('LibraryController', () {
    late _FakeLibraryStore libraryStore;
    late _FakeBookStorageService storageService;
    late _FakeReadingProgressStore progressStore;

    Future<LibraryController> buildController({
      List<LibraryBook> initialBooks = const [],
    }) async {
      libraryStore = _FakeLibraryStore()..saved = initialBooks;
      storageService = _FakeBookStorageService();
      progressStore = _FakeReadingProgressStore();
      final controller = LibraryController(
        libraryStore: libraryStore,
        storageService: storageService,
        progressStore: progressStore,
      );
      await _waitForInitialLoad(controller);
      return controller;
    }

    test('an empty library loads with isEmpty true and no visible books', () async {
      final controller = await buildController();

      expect(controller.isEmpty, isTrue);
      expect(controller.visibleBooks, isEmpty);
    });

    test('importing a new book adds it to the library and stores it durably', () async {
      final controller = await buildController();

      final book = await controller.importBook(_fakePickedFile('Alpha.txt', 100));

      expect(controller.isEmpty, isFalse);
      expect(controller.visibleBooks, hasLength(1));
      expect(controller.visibleBooks.first.identityKey, book.identityKey);
      expect(storageService.storeCalls, ['Alpha.txt::100']);
      expect(libraryStore.saveCallCount, greaterThan(0));
    });

    test(
      'DUPLICATE DETECTION: importing the same file twice reuses the existing entry '
      'instead of creating a second one or copying the file again',
      () async {
        final controller = await buildController();
        final file = _fakePickedFile('Beta.txt', 200);

        final first = await controller.importBook(file);
        final second = await controller.importBook(file);

        expect(controller.visibleBooks, hasLength(1));
        expect(second.identityKey, first.identityKey);
        expect(storageService.storeCalls, hasLength(1));
      },
    );

    test('re-importing an existing book still refreshes lastOpenedAt', () async {
      final controller = await buildController();
      final file = _fakePickedFile('Gamma.txt', 50);

      final first = await controller.importBook(file);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await controller.importBook(file);

      expect(second.lastOpenedAt.isAfter(first.lastOpenedAt), isTrue);
    });

    test('search filters by name, case-insensitively, without affecting the underlying library', () async {
      final controller = await buildController();
      await controller.importBook(_fakePickedFile('Pride and Prejudice.txt', 10));
      await controller.importBook(_fakePickedFile('Moby Dick.txt', 10));

      controller.setSearchQuery('pride');

      expect(controller.visibleBooks, hasLength(1));
      expect(controller.visibleBooks.first.name, 'Pride and Prejudice.txt');
      expect(controller.isEmpty, isFalse, reason: 'isEmpty reflects the WHOLE library, not the search filter');
    });

    test('an empty search query shows every book again', () async {
      final controller = await buildController();
      await controller.importBook(_fakePickedFile('One.txt', 10));
      await controller.importBook(_fakePickedFile('Two.txt', 10));

      controller.setSearchQuery('one');
      expect(controller.visibleBooks, hasLength(1));

      controller.setSearchQuery('');
      expect(controller.visibleBooks, hasLength(2));
    });

    test('sorting by title orders books alphabetically, case-insensitively', () async {
      final controller = await buildController();
      await controller.importBook(_fakePickedFile('Zebra.txt', 10));
      await controller.importBook(_fakePickedFile('apple.txt', 10));

      controller.setSortOrder(LibrarySortOrder.title);

      expect(
        controller.visibleBooks.map((b) => b.name).toList(),
        ['apple.txt', 'Zebra.txt'],
      );
    });

    test('sorting by recently imported puts the newest import first', () async {
      final controller = await buildController();
      await controller.importBook(_fakePickedFile('First.txt', 10));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await controller.importBook(_fakePickedFile('Second.txt', 10));

      controller.setSortOrder(LibrarySortOrder.recentlyImported);

      expect(controller.visibleBooks.first.name, 'Second.txt');
    });

    test(
      'ATOMIC DELETION: removes the library entry, the stored file, and reading progress together',
      () async {
        final controller = await buildController();
        final book = await controller.importBook(_fakePickedFile('Gone.txt', 10));
        await progressStore.save(
          ReadingProgress(
            bookPath: book.identityKey,
            characterOffset: 5,
            totalCharacters: 10,
            lastReadAt: DateTime.now(),
          ),
        );

        await controller.deleteBook(book);

        expect(controller.visibleBooks, isEmpty);
        expect(storageService.deleteCalls, contains(book.storedPath));
        expect(progressStore.saved.containsKey(book.identityKey), isFalse);
        expect(progressStore.clearCalls, contains(book.identityKey));
      },
    );

    test('deleteBook does not throw even when the underlying file is already missing', () async {
      final controller = await buildController();
      final book = await controller.importBook(_fakePickedFile('AlreadyGone.txt', 10));
      storageService.missingPaths.add(book.storedPath);

      await expectLater(controller.deleteBook(book), completes);
      expect(controller.visibleBooks, isEmpty);
    });

    test(
      'MISSING FILE HANDLING: a book whose stored file cannot be found is flagged via '
      'isFileMissing on load, without throwing',
      () async {
        final missingBook = LibraryBook(
          identityKey: 'Ghost.txt::10',
          name: 'Ghost.txt',
          format: SupportedBookFormat.plainText,
          sizeInBytes: 10,
          storedPath: '/fake/library_books/Ghost.txt::10',
          importedAt: DateTime.now(),
          lastOpenedAt: DateTime.now(),
        );

        libraryStore = _FakeLibraryStore()..saved = [missingBook];
        storageService = _FakeBookStorageService()
          ..missingPaths.add(missingBook.storedPath);
        progressStore = _FakeReadingProgressStore();

        final controller = LibraryController(
          libraryStore: libraryStore,
          storageService: storageService,
          progressStore: progressStore,
        );

        await expectLater(_waitForInitialLoad(controller), completes);

        expect(controller.visibleBooks, hasLength(1));
        expect(controller.isFileMissing(controller.visibleBooks.first), isTrue);
      },
    );

    test('a corrupted/unparseable saved library (LibraryStore returning nothing) loads as empty, not a crash', () async {
      // LibraryStore.loadAll() ALREADY guarantees this at the store layer
      // (see its own doc comment on per-entry try/catch) — this test
      // confirms the CONTROLLER built on top of that guarantee behaves
      // correctly for the "nothing survived parsing" case, rather than
      // assuming a non-empty list.
      final controller = await buildController(initialBooks: const []);
      expect(controller.isEmpty, isTrue);
      expect(controller.isLoading, isFalse);
    });

    test('continueReadingBook returns the most recently opened book that has progress', () async {
      final controller = await buildController();
      final a = await controller.importBook(_fakePickedFile('A.txt', 100));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = await controller.importBook(_fakePickedFile('B.txt', 100));

      await progressStore.save(
        ReadingProgress(bookPath: a.identityKey, characterOffset: 10, totalCharacters: 100, lastReadAt: DateTime.now()),
      );
      await progressStore.save(
        ReadingProgress(bookPath: b.identityKey, characterOffset: 20, totalCharacters: 100, lastReadAt: DateTime.now()),
      );
      await controller.refreshProgress();

      // b was imported (and therefore opened) more recently than a.
      expect(controller.continueReadingBook?.identityKey, b.identityKey);
      expect(controller.progressFractionFor(b), 0.2);
    });

    test('a book with no saved progress is never offered as Continue Reading', () async {
      final controller = await buildController();
      await controller.importBook(_fakePickedFile('NeverOpened.txt', 100));

      expect(controller.continueReadingBook, isNull);
    });

    test(
      'a finished book (progress cleared by BookReaderController on completion) drops '
      'out of Continue Reading, matching Module 6\'s existing completion behavior',
      () async {
        final controller = await buildController();
        final book = await controller.importBook(_fakePickedFile('Finished.txt', 100));
        await progressStore.save(
          ReadingProgress(bookPath: book.identityKey, characterOffset: 50, totalCharacters: 100, lastReadAt: DateTime.now()),
        );
        await controller.refreshProgress();
        expect(controller.continueReadingBook, isNotNull);

        // Simulates BookReaderController._handleChunkCompletion clearing
        // progress once a book is fully finished.
        await progressStore.clear(book.identityKey);
        await controller.refreshProgress();

        expect(controller.continueReadingBook, isNull);
      },
    );
  });
}
