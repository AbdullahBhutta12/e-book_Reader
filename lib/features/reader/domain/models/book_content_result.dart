import 'book_content.dart';

/// Every possible outcome of attempting to load and extract a book's
/// content for display.
///
/// Same reasoning as [BookImportResult] in Module 2: modeling every
/// outcome as its own type (rather than a nullable `BookContent?`) lets
/// the UI show a specific, honest state for each case, and lets Dart's
/// exhaustive `switch` guarantee every case is handled.
sealed class BookContentResult {
  const BookContentResult();
}

/// The book's content was extracted successfully and is ready to display.
final class BookContentLoaded extends BookContentResult {
  const BookContentLoaded(this.content);
  final BookContent content;
}

/// This book's file format doesn't have a [TextExtractor] registered yet.
///
/// This is the case for `.pdf` and `.epub` in V1 — they were valid,
/// recognized formats back in Module 2's import step, but Module 3 only
/// ships a plain-text extractor. This is NOT a bug or a crash — it's an
/// honest, expected state the UI shows the user.
final class BookContentUnsupportedFormat extends BookContentResult {
  const BookContentUnsupportedFormat(this.extension);
  final String extension;
}

/// The format was supported, but reading the file itself failed (e.g.
/// the file was moved or deleted after import, a permissions error, or
/// corrupted content).
final class BookContentLoadFailure extends BookContentResult {
  const BookContentLoadFailure(this.message);
  final String message;
}
