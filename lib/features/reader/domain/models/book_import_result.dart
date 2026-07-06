import 'book_file.dart';

/// Every possible outcome of attempting to import a book file.
///
/// WHY A SEALED CLASS (a Dart 3 language feature) INSTEAD OF A NULLABLE
/// `BookFile?` OR THROWING EXCEPTIONS:
///
/// A nullable return (`BookFile? pickBook()`) can only distinguish "it
/// worked" from "it didn't" — it can't tell the UI *why* it didn't, so
/// the UI can't show a helpful, specific message.
///
/// Throwing exceptions for everyday, expected outcomes (like "the user
/// tapped Cancel on the file picker") is considered poor practice —
/// exceptions are meant to signal *exceptional*, unanticipated failures,
/// not routine branches of your business logic.
///
/// A `sealed class` lets us model every real outcome as its own type.
/// Combined with Dart's *exhaustive switch* (you'll see this in
/// `home_screen.dart`), the compiler forces whoever consumes a
/// `BookImportResult` to handle every single case. If we add a fifth
/// outcome here later and forget to handle it in the UI, that's a
/// compile-time error — not a bug a user finds for us in production.
sealed class BookImportResult {
  const BookImportResult();
}

/// The user picked a real, valid, supported book file.
final class BookImportSuccess extends BookImportResult {
  const BookImportSuccess(this.book);
  final BookFile book;
}

/// The user closed the file picker without selecting anything.
/// This is NOT an error condition — cancelling is a completely normal,
/// expected user action, and the UI should do nothing but reset silently.
final class BookImportCancelled extends BookImportResult {
  const BookImportCancelled();
}

/// The user selected a real file, but its extension isn't one we
/// currently support (e.g. a `.mobi` or a `.docx`).
final class BookImportUnsupportedFormat extends BookImportResult {
  const BookImportUnsupportedFormat(this.extension);
  final String extension;
}

/// Something unexpected went wrong while picking or reading the file
/// (e.g. an I/O error, or the OS returning incomplete file metadata).
final class BookImportFailure extends BookImportResult {
  const BookImportFailure(this.message);
  final String message;
}
