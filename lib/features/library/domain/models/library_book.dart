import '../../../reader/domain/models/book_file.dart';
import '../../../reader/domain/models/supported_book_format.dart';

/// A book that has been imported into this app's persistent library —
/// distinct from `BookFile`, which represents a freshly-picked file that
/// hasn't necessarily been durably stored yet.
///
/// WHY THIS IS A SEPARATE MODEL FROM `BookFile` (not just `BookFile`
/// reused as-is):
/// `BookFile.path` means "wherever `file_picker` happened to put its
/// transient cache copy this time" — exactly the value Module 6 learned
/// NOT to persist anywhere, since it isn't stable across repeated picks
/// of the same source file. `LibraryBook.storedPath` means something
/// different and much stronger: "the path to THIS APP'S OWN durable copy,
/// in a directory it owns and controls" (see `BookStorageService`) — a
/// value that stays valid across app restarts, and even if the ORIGINAL
/// source file the user picked is later deleted, moved, or otherwise
/// becomes unreachable. Giving these two genuinely different guarantees
/// two different types means the compiler — not a comment, not
/// discipline — is what stops a `BookFile.path` from ever being persisted
/// as if it meant the same thing `LibraryBook.storedPath` does.
///
/// WHY `identityKey` REUSES `BookFile.identityKey` VERBATIM (name + exact
/// byte size), RATHER THAN INVENTING A SEPARATE SCHEME:
/// This is the identical identity `ReadingProgressStore` already keys
/// progress on. Using a different identity scheme here would reproduce
/// the exact class of bug Module 6 fixed once already — a library entry
/// and its own reading progress silently unable to find each other.
class LibraryBook {
  const LibraryBook({
    required this.identityKey,
    required this.name,
    required this.format,
    required this.sizeInBytes,
    required this.storedPath,
    required this.importedAt,
    required this.lastOpenedAt,
  });

  final String identityKey;
  final String name;
  final SupportedBookFormat format;
  final int sizeInBytes;

  /// The path to this app's OWN durable copy of the book's bytes —
  /// never `file_picker`'s transient path. See this class's own doc
  /// comment above for why that distinction is the entire point of this
  /// model existing.
  final String storedPath;

  final DateTime importedAt;

  /// Updated every time this book is opened (a fresh import, or tapping
  /// it in the library list) — the basis for "recently opened" sorting
  /// and for picking which book the Continue Reading card features.
  final DateTime lastOpenedAt;

  /// Human-friendly size, e.g. "2.43 MB" — reuses `BookFile`'s own
  /// formatting logic (`BookFile.formatBytes`) rather than a second,
  /// separately-maintained copy of the same byte-to-string math.
  String get formattedSize => BookFile.formatBytes(sizeInBytes);

  /// Builds the `BookFile` `BookReaderController` actually needs to open
  /// this book — pointed at `storedPath` (this app's durable copy), NOT
  /// at wherever the original pick came from. This is the concrete
  /// mechanism behind "imported books keep working even if the original
  /// source file is deleted or moved": from the moment a book is in the
  /// library, absolutely nothing about reading it ever looks at the
  /// original file again.
  BookFile toBookFile() {
    return BookFile(
      name: name,
      path: storedPath,
      format: format,
      sizeInBytes: sizeInBytes,
    );
  }

  /// Returns a copy with [lastOpenedAt] updated — the only field this
  /// model ever needs to change after creation. Everything else about a
  /// library entry (its identity, its durable copy, when it was first
  /// imported) is fixed for the entry's whole lifetime.
  LibraryBook copyWith({DateTime? lastOpenedAt}) {
    return LibraryBook(
      identityKey: identityKey,
      name: name,
      format: format,
      sizeInBytes: sizeInBytes,
      storedPath: storedPath,
      importedAt: importedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}
