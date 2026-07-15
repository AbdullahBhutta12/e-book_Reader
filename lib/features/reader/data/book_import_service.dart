import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
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
  ///
  /// STABILITY PATCH: this method's body is now wrapped in a `try/catch`.
  /// Before this patch, an exception thrown by the underlying native
  /// picker — a `PlatformException` (a real, documented possibility:
  /// Android's document picker can fail if the user's default file
  /// provider crashes, is mid-update, or denies the request) or any
  /// other unexpected error — would propagate straight out of this
  /// method as an uncaught exception. Whoever called `pickBook()` would
  /// have no [BookImportResult] to switch on at all; in `HomeScreen`,
  /// that meant the `await` would throw before `_isImporting` was ever
  /// reset back to `false`, leaving the button stuck showing a spinner
  /// forever. Catching every failure here and returning a proper
  /// [BookImportFailure] means this method now has exactly one contract,
  /// with no exceptions (in either sense of the word): it always
  /// completes with a [BookImportResult].
  Future<BookImportResult> pickBook() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: SupportedBookFormat.allExtensions,
        // We only need this file's path and metadata right now — not its
        // full contents loaded into memory. Requesting bytes we don't
        // need yet risks an out-of-memory crash on a large book, and
        // Module 3 reads the file's contents from disk itself when it's
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

      // Defensive check: in rare edge cases (some cloud-storage
      // providers, unusual file systems) the OS can return a "selected"
      // file without a usable path or extension. We never assume
      // external data is well-formed — we treat this as an explicit
      // failure instead of letting a broken BookFile flow deeper into
      // the app.
      if (path == null || rawExtension == null) {
        return const BookImportFailure(AppStrings.importGenericError);
      }

      // Even though we already asked the OS picker to filter by
      // extension above, we NEVER trust that filtering alone — some
      // devices and cloud providers don't enforce it strictly, and a
      // user could rename a file to bypass it. We re-validate ourselves
      // before trusting this file any further.
      final SupportedBookFormat? format =
          SupportedBookFormat.fromExtension(rawExtension);
      if (format == null) {
        return BookImportUnsupportedFormat(rawExtension);
      }

      final book = BookFile(
        name: picked.name,
        path: path,
        format: format,
        sizeInBytes: picked.size,
      );

      return BookImportSuccess(book);
    } on PlatformException {
      // Named explicitly (rather than falling through to the generic
      // `catch` below) because this is the specific, documented
      // exception type Android's native picker throws — e.g. if the
      // system's document provider crashes or refuses the request. It's
      // still reported through the same BookImportFailure the user sees
      // for any other failure; the separate `on` clause exists so this
      // known case is easy to spot in the code, not to handle it
      // differently.
      return const BookImportFailure(AppStrings.importGenericError);
    } catch (_) {
      // Catch-all safety net for anything else unexpected. Deliberately
      // broad: the whole point of this patch is that NOTHING escapes
      // this method uncaught, regardless of what it turns out to be.
      return const BookImportFailure(AppStrings.importGenericError);
    }
  }
}
