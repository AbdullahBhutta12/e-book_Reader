import '../domain/models/supported_book_format.dart';
import '../domain/services/text_extractor.dart';
import 'plain_text_extractor.dart';

/// Selects the right [TextExtractor] for a given [SupportedBookFormat] —
/// or reports that none exists yet.
///
/// This is the single place in the whole app that knows "which concrete
/// extractor handles which format." Adding PDF or EPUB support later
/// means writing a new extractor class and adding ONE new case here —
/// nothing else in the app changes.
class TextExtractorFactory {
  const TextExtractorFactory();

  /// Returns the extractor for [format], or `null` if this version of
  /// the app doesn't know how to read that format yet.
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
