import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../reader/domain/models/book_file.dart';

/// Copies a freshly-picked book's bytes into a directory this app owns
/// and controls, and cleans that copy up again on deletion.
///
/// WHY THIS CLASS LIVES IN `data/`, NOT `domain/`:
/// Same reasoning as `BookImportService` and `TtsService` in the reader
/// feature: this is the ONLY file in the whole app that imports
/// `package:path_provider` — a third-party plugin that talks to the
/// platform's file system. If this app ever needed a different storage
/// strategy, only this file would change.
///
/// WHY THIS EXISTS AT ALL — the concrete mechanism behind "imported
/// books keep working even if the original source file is deleted or
/// moved": `file_picker`'s own returned path is a copy in ITS transient
/// cache, not something this app owns any lifecycle guarantee over (see
/// `BookFile.identityKey`'s doc comment for the bug that taught us this
/// the hard way). `getApplicationDocumentsDirectory()` is different: it's
/// a directory the OS promises belongs to this app and won't be cleared
/// out from under it. Copying a book's bytes there, once, at import time,
/// is what lets the library point at something durable instead of at
/// whatever `file_picker` happens to be holding onto this session.
class BookStorageService {
  const BookStorageService();

  static const String _booksDirectoryName = 'library_books';

  /// Copies [source]'s bytes into durable storage and returns the new,
  /// durable path. Safe to call more than once for the "same" book
  /// (same `identityKey`) — the destination filename is DERIVED from
  /// `identityKey` deterministically, so a repeat call lands on the same
  /// destination and short-circuits without copying again, rather than
  /// accumulating duplicate copies on disk.
  ///
  /// WHY THE DESTINATION FILENAME IS A SANITIZED `identityKey`, NOT A
  /// GENERATED UNIQUE NAME: a deterministic destination is what makes
  /// the short-circuit above possible at all, and it's also what keeps
  /// `LibraryController`'s duplicate-detection (checking the LIBRARY
  /// STORE for an existing `identityKey` before ever calling this)
  /// consistent with what's actually on disk — the same identity always
  /// maps to the same file, in both places.
  Future<String> store(BookFile source) async {
    final Directory booksDir = await _booksDirectory();
    final String destinationPath =
        '${booksDir.path}/${_sanitizeForFileName(source.identityKey)}';

    final File destination = File(destinationPath);
    if (await destination.exists()) {
      // Already stored — this is the "re-importing the same book"
      // short-circuit described above. `LibraryController` also checks
      // for this at the library-entry level before ever calling `store`;
      // this is a second, cheap, defense-in-depth check directly against
      // the file system itself, in case the two ever drifted out of
      // sync (e.g. a library entry lost without its file being cleaned
      // up).
      return destinationPath;
    }

    await File(source.path).copy(destinationPath);
    return destinationPath;
  }

  /// Deletes the durable copy at [storedPath]. Safe to call even if the
  /// file is already gone — deletion is inherently "make sure this
  /// doesn't exist," not "assert that it did."
  Future<void> delete(String storedPath) async {
    final File file = File(storedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Checks whether a durable copy still exists at [storedPath]. Used by
  /// `LibraryController` to detect a missing or externally-removed file
  /// without ever needing to attempt reading it — a plain existence
  /// check can't throw the way an actual file read could, which is
  /// exactly why this is a separate, deliberately minimal method rather
  /// than folding the check into `store` or `delete`.
  Future<bool> exists(String storedPath) => File(storedPath).exists();

  Future<Directory> _booksDirectory() async {
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    final Directory booksDir =
        Directory('${documentsDir.path}/$_booksDirectoryName');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }

  /// `identityKey` is `"<name>::<sizeInBytes>"` — safe as a JSON value or
  /// a map key, but not guaranteed safe as a FILE NAME (a book's original
  /// name can contain spaces or other characters some file systems
  /// reject). This keeps only characters every target platform accepts,
  /// replacing everything else with `_`. Deliberately simple (no hashing,
  /// no external package) — this only needs to be deterministic and
  /// collision-free for names that already differ, which a straight
  /// character substitution already guarantees.
  String _sanitizeForFileName(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
