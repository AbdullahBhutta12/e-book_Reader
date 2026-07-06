import 'dart:io';
import '../domain/models/book_content.dart';
import '../domain/models/book_file.dart';
import '../domain/services/text_extractor.dart';

/// Extracts [BookContent] from a plain `.txt` file.
///
/// This is the ONLY [TextExtractor] implementation in V1 — see the
/// architecture review for why TXT was chosen as the sole supported
/// reading format for this version.
class PlainTextExtractor implements TextExtractor {
  const PlainTextExtractor();

  @override
  Future<BookContent> extract(BookFile book) async {
    final String raw = await File(book.path).readAsString();
    return _buildContent(raw);
  }

  /// Turns raw file text into clean, TTS-ready paragraphs.
  ///
  /// WHY WE SPLIT ON BLANK LINES, NOT EVERY LINE BREAK:
  /// Most plain-text books (Project Gutenberg exports, manuscripts, etc.)
  /// are hard-wrapped at a fixed column width — a single `\n` is usually
  /// just where a line happened to end on the page, not a real paragraph
  /// break. Treating every line break as a new paragraph would chop
  /// sentences apart mid-thought. A REAL paragraph break is a blank line
  /// (one or more consecutive line breaks with only whitespace between
  /// them), so that's what we split on. Line breaks *inside* a paragraph
  /// are then collapsed into single spaces, turning the hard-wrapped
  /// lines back into continuous, naturally-flowing prose — which is
  /// exactly what both the on-screen reading view and (in Module 4) the
  /// TTS engine want to receive.
  BookContent _buildContent(String raw) {
    final List<String> rawParagraphs = raw.split(RegExp(r'\n\s*\n'));

    final buffer = StringBuffer();
    final paragraphs = <BookParagraph>[];

    for (final rawParagraph in rawParagraphs) {
      final String cleaned =
          rawParagraph.replaceAll(RegExp(r'\s+'), ' ').trim();

      // Skips stray empty chunks — e.g. leading/trailing blank lines at
      // the very start or end of the file produce an empty "paragraph"
      // after splitting, which we don't want to render as a blank card.
      if (cleaned.isEmpty) continue;

      final int start = buffer.length;
      buffer.write(cleaned);
      final int end = buffer.length;

      paragraphs.add(
        BookParagraph(text: cleaned, startOffset: start, endOffset: end),
      );

      // Kept IN fullText (not just between paragraph objects) so that
      // fullText stays a byte-for-byte-consistent global offset space —
      // every BookParagraph's offsets must always point to exactly what's
      // really at that position in fullText.
      buffer.write('\n\n');
    }

    return BookContent(fullText: buffer.toString(), paragraphs: paragraphs);
  }
}
