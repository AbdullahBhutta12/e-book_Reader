import '../domain/models/supported_book_format.dart';
import '../domain/services/text_extractor.dart';
import 'plain_text_extractor.dart';

/// Selects the right [TextExtractor] for a given [SupportedBookFormat] —
/// or reports that none exists yet.
///
/// This is the single place in the whole app that knows "which concrete
/// extractor handles which format" — equivalently, this class IS the
/// definition of "readable in this version" (see [SupportedBookFormat]'s
/// doc comment for why that's kept separate from "recognized"). Adding
/// PDF or EPUB support later means writing a new extractor class (e.g.
/// `PdfExtractor`, `EpubExtractor`) and changing the two lines below that
/// currently `return null` for them — nothing in `BookReaderController`,
/// `ReaderScreen`, or any other file needs to change at all.
class TextExtractorFactory {
  const TextExtractorFactory();

  /// Returns the extractor for [format], or `null` if this version of
  /// the app doesn't know how to read that format yet. A `null` here is
  /// the ONLY thing that means "not yet readable" anywhere in the app —
  /// callers turn it into a [BookContentNotYetReadable] result rather
  /// than treating it as an error.
  ///
  /// WHY THIS SWITCH HAS NO `default:` CASE:
  /// Same Dart 3 exhaustiveness guarantee we relied on in Module 2. Every
  /// value of [SupportedBookFormat] is handled explicitly — `pdf` and
  /// `epub` deliberately return `null` for now, rather than being
  /// silently caught by a `default`. If a fourth format is ever added to
  /// the enum and someone forgets to add a case for it here, this won't
  /// compile until they do.
  TextExtractor? extractorFor(SupportedBookFormat format) {
    switch (format) {
      case SupportedBookFormat.plainText:
        return const PlainTextExtractor();
      case SupportedBookFormat.pdf:
      case SupportedBookFormat.epub:
        return null;
    }
  }
}
