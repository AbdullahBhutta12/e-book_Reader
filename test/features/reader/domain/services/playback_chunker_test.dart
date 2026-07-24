import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_reader/features/reader/domain/models/book_content.dart';
import 'package:ebook_reader/features/reader/domain/services/playback_chunker.dart';

/// Builds a [BookContent] the same way [PlainTextExtractor] does: each
/// paragraph's text is written into a shared buffer with `\n\n` between
/// entries, and its offsets point at exactly where it landed — so these
/// tests exercise [PlaybackChunker] against the real global-offset shape
/// it's actually handed in production, not a simplified stand-in for it.
BookContent _contentFrom(List<String> paragraphTexts) {
  final buffer = StringBuffer();
  final paragraphs = <BookParagraph>[];

  for (final text in paragraphTexts) {
    final start = buffer.length;
    buffer.write(text);
    final end = buffer.length;
    paragraphs.add(BookParagraph(text: text, startOffset: start, endOffset: end));
    buffer.write('\n\n');
  }

  return BookContent(fullText: buffer.toString(), paragraphs: paragraphs);
}

void main() {
  group('PlaybackChunker', () {
    test('a short book produces exactly one chunk', () {
      const chunker = PlaybackChunker();
      final content = _contentFrom(['A short first paragraph.', 'And a second one.']);

      final chunks = chunker.chunk(content);

      expect(chunks.length, 1);
    });

    test('an empty book produces no chunks, without crashing', () {
      const chunker = PlaybackChunker();
      final content = _contentFrom(const []);

      final chunks = chunker.chunk(content);

      expect(chunks, isEmpty);
    });

    test('no chunk ever exceeds maxChunkLength', () {
      // A small limit deliberately forces the packing/splitting logic to
      // actually engage, rather than every paragraph trivially fitting
      // in one chunk the way a real 2000-character default usually does
      // for ordinary paragraphs.
      const chunker = PlaybackChunker(maxChunkLength: 50);
      final content = _contentFrom([
        'This is the first paragraph and it is reasonably long for a test.',
        'A second paragraph, also fairly long, to force packing decisions.',
        'Short one.',
        'Another short paragraph here.',
      ]);

      final chunks = chunker.chunk(content);

      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(
          chunk.text.length,
          lessThanOrEqualTo(50),
          reason: 'chunk "${chunk.text}" exceeds the configured limit',
        );
      }
    });

    test('short consecutive paragraphs are packed into one chunk, not one each', () {
      const chunker = PlaybackChunker(); // default 2000-char limit
      final content = _contentFrom([
        'One.',
        'Two.',
        'Three.',
        'Four.',
        'Five.',
      ]);

      final chunks = chunker.chunk(content);

      // Five tiny paragraphs, all well under the default limit combined,
      // should be packed together rather than producing five separate
      // speak() calls — the entire reason packing exists.
      expect(chunks.length, 1);
    });

    test('a single oversized paragraph is split without breaking any word', () {
      const chunker = PlaybackChunker(maxChunkLength: 30);
      final longParagraph =
          'This paragraph is intentionally much longer than the configured '
          'chunk limit so that the sentence and hard-split fallbacks both '
          'have to engage in order to break it apart safely.';
      final content = _contentFrom([longParagraph]);

      final chunks = chunker.chunk(content);

      expect(chunks.length, greaterThan(1));

      // Reassemble every chunk's text and confirm every word from the
      // original paragraph still appears intact, in order — the direct
      // test of "never breaks a word."
      final originalWords = longParagraph.split(RegExp(r'\s+'));
      final rebuiltWords =
          chunks.map((c) => c.text.trim()).join(' ').split(RegExp(r'\s+'));
      expect(rebuiltWords, originalWords);
    });

    test('chunk offsets are valid substrings of fullText', () {
      const chunker = PlaybackChunker(maxChunkLength: 40);
      final content = _contentFrom([
        'Paragraph one is here.',
        'Paragraph two follows after it.',
        'And a third, final paragraph.',
      ]);

      final chunks = chunker.chunk(content);

      for (final chunk in chunks) {
        expect(
          content.fullText.substring(chunk.startOffset, chunk.endOffset),
          chunk.text,
          reason: 'chunk.text must be the REAL substring at its own '
              'offsets, not text rebuilt separately from it',
        );
      }
    });

    test('maxChunkLength defaults to PlaybackChunker.defaultMaxChunkLength', () {
      const chunker = PlaybackChunker();
      expect(chunker.maxChunkLength, PlaybackChunker.defaultMaxChunkLength);
      expect(PlaybackChunker.defaultMaxChunkLength, 2000);
    });
  });
}
