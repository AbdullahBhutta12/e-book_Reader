import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_strings.dart';
import '../domain/models/book_file.dart';
import '../domain/models/book_import_result.dart';
import '../domain/models/supported_book_format.dart';

/// Talks to the device's native file picker and turns its raw, messy
/// result into a clean, typed [BookImportResult].
///
/// WHY THIS CLASS LIVES IN `data/`, NOT `domain/`:
/// This is the ONLY file in the `reader` feature that imports
/// `package:file_picker` — a third-party plugin that talks to the
/// operating system. Talking to an external data source (the OS, a
/// database, a network API) is exactly what the `data/` layer is for. If
/// this app ever swaps `file_picker` for a different package, or gains a
/// second way to import a book (e.g. "from Google Drive" in a later
/// module), only files in `data/` change — `domain/` and `presentation/`
/// never need to know or care.
class BookImportService {
  const BookImportService();

  /// Opens the native file picker restricted to supported book
  /// extensions, and returns exactly what happened as a
  /// [BookImportResult].
  Future<BookImportResult> pickBook() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: SupportedBookFormat.allExtensions,
      // We only need this file's path and metadata right now — not its
      // full contents loaded into memory. Requesting bytes we don't need
      // yet risks an out-of-memory crash on a large book, and Module 3
      // will read the file's contents from disk itself when it's
      // actually needed.
      withData: false,
    );

    // The user backed out of the picker (tapped back / outside the
    // dialog) without choosing anything. This is normal, not an error.
    if (result == null || result.files.isEmpty) {
      return const BookImportCancelled();
    }

    final PlatformFile picked = result.files.single;
    final String? path = picked.path;
    final String? rawExtension = picked.extension;

    // Defensive check: in rare edge cases (some cloud-storage providers,
    // unusual file systems) the OS can return a "selected" file without a
    // usable path or extension. We never assume external data is
    // well-formed — we treat this as an explicit failure instead of
    // letting a broken BookFile flow deeper into the app.
    if (path == null || rawExtension == null) {
      return const BookImportFailure(AppStrings.importGenericError);
    }

    // Even though we already asked the OS picker to filter by extension
    // above, we NEVER trust that filtering alone — some devices and cloud
    // providers don't enforce it strictly, and a user could rename a file
    // to bypass it. We re-validate ourselves before trusting this file
    // any further.
    final SupportedBookFormat? format =
        SupportedBookFormat.fromExtension(rawExtension);
    if (format == null) {
      return BookImportUnsupportedFormat(rawExtension);
    }

    final book = BookFile(
      name: picked.name,
      path: path,
      extension: format.extension,
      sizeInBytes: picked.size,
    );

    return BookImportSuccess(book);
  }
}
