import 'supported_book_format.dart';

/// Immutable, validated representation of a book file the user picked
/// from their device.
///
/// WHY THIS CLASS HAS ZERO IMPORTS FROM `file_picker`:
/// This is a *domain model* — it represents the concept of "a book file"
/// as our app understands it, independent of how it was obtained. It
/// doesn't know what `file_picker`, `PlatformFile`, or Android's Storage
/// Access Framework even are. That separation means:
///   - The UI layer (`ReaderScreen`) only ever depends on this simple,
///     stable class — never on a third-party plugin's types directly.
///   - If Module 6 adds "import from Google Drive" as a second way to get
///     a book, that new code just needs to produce a `BookFile` too — the
///     UI and any future business logic built on `BookFile` don't change
///     at all.
class BookFile {
  const BookFile({
    required this.name,
    required this.path,
    required this.format,
    required this.sizeInBytes,
  });

  /// Display name, e.g. "Pride and Prejudice.epub".
  final String name;

  /// Absolute path to the file on-device. Module 3 uses this to actually
  /// open and read the file's contents.
  final String path;

  /// This book's recognized format.
  ///
  /// STABILITY PATCH: this used to be a raw `String extension` with a doc
  /// comment saying it was "guaranteed by BookImportService to always be
  /// one of SupportedBookFormat's values." That guarantee was only true
  /// by convention — nothing stopped a future edit to
  /// `BookImportService` from constructing a `BookFile` with an
  /// unvalidated string. Storing the enum itself instead of a string
  /// makes the guarantee impossible to violate: there is no
  /// `BookFile(format: 'mobi')` you could accidentally write, because
  /// `'mobi'` isn't a `SupportedBookFormat` value. This is the "make
  /// invalid states unrepresentable" principle — moving an invariant out
  /// of a comment and into the type system.
  ///
  /// The original raw extension string is never lost — it's always
  /// available as `format.extension` (see `SupportedBookFormat`).
  final SupportedBookFormat format;

  /// Raw file size in bytes, exactly as reported by the OS.
  final int sizeInBytes;

  /// A stable identifier for "this book," usable as a persistence key —
  /// unlike [path], which is NOT safe to use for that purpose.
  ///
  /// ROOT-CAUSE NOTE (Module 6 resume-progress bug): [path] comes from
  /// whatever `file_picker` happened to hand back for a given pick — and
  /// on Android, `file_picker` copies the picked document into this
  /// app's cache directory under a freshly-generated subdirectory EVERY
  /// time `pickBook()` runs, even when the user picks the exact same
  /// underlying file twice in a row. Since this app has no persisted
  /// library (re-opening a book always means picking it again from
  /// `HomeScreen`), `path` is effectively a new, unpredictable value
  /// every single session — never a stable one.
  ///
  /// `ReadingProgressStore` originally used `path` as its lookup key on
  /// the (reasonable-sounding, but false) assumption that "the physical
  /// file path is already this app's authoritative identity for a
  /// book." That assumption is what silently broke resume: progress was
  /// always saved correctly under one session's path and then looked up
  /// under a different, never-matching path the next session, so
  /// `load()` always returned `null` — indistinguishable, from the
  /// store's point of view, from "no progress was ever saved."
  ///
  /// `name` + `sizeInBytes` are exactly what DOES survive across
  /// separate picks of the same source file (the OS reports the same
  /// display name and byte size for it every time), so combining them
  /// gives a key that's stable across app restarts without requiring a
  /// real content hash or a persisted library.
  String get identityKey => '$name::$sizeInBytes';

  /// Human-friendly size, e.g. "2.43 MB".
  ///
  /// WHY THIS IS A GETTER, NOT A STORED FIELD:
  /// "2.43 MB" is a *display* concern, derived on demand from
  /// `sizeInBytes`. Storing it as a field would mean carrying redundant
  /// data that could theoretically drift out of sync with the real size —
  /// computing it on read means there's only ever one source of truth.
  String get formattedSize => formatBytes(sizeInBytes);

  /// MODULE 8: extracted from what used to be [formattedSize]'s own
  /// inline body, so `LibraryBook` (a separate model that also has a
  /// `sizeInBytes` to display) can reuse the exact same formatting logic
  /// instead of a second, separately-maintained copy of it.
  static String formatBytes(int bytes) {
    const int kb = 1024;
    const int mb = kb * 1024;

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }
}
