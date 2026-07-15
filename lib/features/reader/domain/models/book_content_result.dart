import 'book_content.dart';
import 'supported_book_format.dart';

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

/// This book's format is RECOGNIZED (it's a real [SupportedBookFormat]
/// value — `.pdf`, `.epub`, or `.txt`) but doesn't have a [TextExtractor]
/// registered yet, so it can't be READ in this version.
///
/// STABILITY PATCH — naming: this class used to be called
/// `BookContentUnsupportedFormat`, which reads as if the file itself is
/// invalid. It isn't — `BookImportService` already validated it as a
/// real, recognized book format back at import time; "recognized" and
/// "readable" are two different, separate questions, and this type only
/// ever represents the second one being "not yet." The rename to
/// `BookContentNotYetReadable` says that directly, and the field is now
/// the actual [SupportedBookFormat] enum (guaranteed valid, since it can
/// only ever be `pdf` or `epub` — `TextExtractorFactory` never returns
/// `null` for `.txt`) instead of a raw extension string.
final class BookContentNotYetReadable extends BookContentResult {
  const BookContentNotYetReadable(this.format);
  final SupportedBookFormat format;
}

/// The format was recognized AND readable, but reading the file itself
/// failed (e.g. the file was moved or deleted after import, a
/// permissions error, or corrupted content).
final class BookContentLoadFailure extends BookContentResult {
  const BookContentLoadFailure(this.message);
  final String message;
}
