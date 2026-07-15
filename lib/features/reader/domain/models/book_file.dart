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

  /// Human-friendly size, e.g. "2.43 MB".
  ///
  /// WHY THIS IS A GETTER, NOT A STORED FIELD:
  /// "2.43 MB" is a *display* concern, derived on demand from
  /// `sizeInBytes`. Storing it as a field would mean carrying redundant
  /// data that could theoretically drift out of sync with the real size —
  /// computing it on read means there's only ever one source of truth.
  String get formattedSize {
    const int kb = 1024;
    const int mb = kb * 1024;

    if (sizeInBytes >= mb) {
      return '${(sizeInBytes / mb).toStringAsFixed(2)} MB';
    } else if (sizeInBytes >= kb) {
      return '${(sizeInBytes / kb).toStringAsFixed(2)} KB';
    }
    return '$sizeInBytes B';
  }
}
