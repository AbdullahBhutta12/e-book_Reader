import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_reader/features/reader/domain/models/book_content.dart';

void main() {
  group('BookContent.paragraphIndexAt', () {
    // Three paragraphs at known offsets, mirroring how PlainTextExtractor
    // actually lays them out (each followed by a "\n\n" gap that belongs
    // to neither paragraph).
    final content = BookContent(
      fullText: 'First para.\n\nSecond para.\n\nThird para.\n\n',
      paragraphs: const [
        BookParagraph(text: 'First para.', startOffset: 0, endOffset: 11),
        BookParagraph(text: 'Second para.', startOffset: 13, endOffset: 25),
        BookParagraph(text: 'Third para.', startOffset: 27, endOffset: 38),
      ],
    );

    test('finds the correct paragraph for an offset in the middle of it', () {
      expect(content.paragraphIndexAt(5), 0);
      expect(content.paragraphIndexAt(18), 1);
      expect(content.paragraphIndexAt(30), 2);
    });

    test('finds the correct paragraph for an offset at its exact start', () {
      expect(content.paragraphIndexAt(0), 0);
      expect(content.paragraphIndexAt(13), 1);
      expect(content.paragraphIndexAt(27), 2);
    });

    test('an offset landing in a gap between paragraphs clamps to a nearby index, never throws', () {
      // Offset 12 is the "\n\n" gap right after paragraph 0 and before
      // paragraph 1 — not inside any paragraph's own [start, end) range.
      expect(() => content.paragraphIndexAt(12), returnsNormally);
      final index = content.paragraphIndexAt(12);
      expect(index, anyOf(0, 1));
    });

    test('an offset before the first paragraph clamps to index 0', () {
      expect(content.paragraphIndexAt(-5), 0);
    });

    test('an offset past the last paragraph clamps to the final index', () {
      expect(content.paragraphIndexAt(9999), 2);
    });

    test('a single-paragraph book always returns index 0', () {
      final single = BookContent(
        fullText: 'Only paragraph.\n\n',
        paragraphs: const [
          BookParagraph(text: 'Only paragraph.', startOffset: 0, endOffset: 15),
        ],
      );
      expect(single.paragraphIndexAt(0), 0);
      expect(single.paragraphIndexAt(7), 0);
      expect(single.paragraphIndexAt(999), 0);
    });
  });
}
