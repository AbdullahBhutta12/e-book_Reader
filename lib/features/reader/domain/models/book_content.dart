/// A single paragraph of extracted book text, plus where it sits within
/// the book's overall character stream.
///
/// WHY WE TRACK OFFSETS PER PARAGRAPH (not just a `List<String>`):
/// Module 4 (Text-to-Speech) will receive character offsets from
/// `flutter_tts`'s progress callback — but those offsets are relative to
/// whatever single string was sent to `speak()`, not to "paragraph 7."
/// Storing each paragraph's [startOffset]/[endOffset] in that same global
/// offset space now means Module 5 (highlighting) can answer "which
/// paragraph is currently being read?" with a simple lookup, instead of
/// re-deriving it later. We're not using this yet in Module 3 — but
/// designing the seam now avoids reworking this data structure later.
class BookParagraph {
  const BookParagraph({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  /// The paragraph's clean, display-ready text (see [PlainTextExtractor]
  /// for how "clean" is defined for a .txt file).
  final String text;

  /// Inclusive index into [BookContent.fullText] where this paragraph
  /// begins.
  final int startOffset;

  /// Exclusive index into [BookContent.fullText] where this paragraph
  /// ends.
  final int endOffset;
}

/// The fully extracted, ready-to-display content of one book.
///
/// This is what every [TextExtractor] implementation ultimately produces,
/// regardless of the source format — the Reader screen only ever depends
/// on this class, never on how it was extracted.
class BookContent {
  const BookContent({
    required this.fullText,
    required this.paragraphs,
  });

  /// The complete extracted text, in one continuous string. This is the
  /// same string Module 4 will hand to the TTS engine, which is exactly
  /// why every [BookParagraph]'s offsets are measured against it.
  final String fullText;

  /// Every paragraph in reading order, each carrying its position within
  /// [fullText].
  final List<BookParagraph> paragraphs;

  /// Finds the index (into [paragraphs]) of the paragraph that contains a
  /// given character offset — e.g. "the TTS engine is currently reading
  /// character 4210, which paragraph is that?"
  ///
  /// WHY BINARY SEARCH: paragraphs are stored in ascending offset order,
  /// so we don't need to check every paragraph one by one. Binary search
  /// finds the answer in O(log n) instead of O(n) — for a long novel with
  /// several thousand paragraphs, that's the difference between a handful
  /// of comparisons and potentially thousands, done every time this is
  /// called (which, once wired to live TTS progress updates in Module 5,
  /// could be many times per second).
  int paragraphIndexAt(int characterOffset) {
    int low = 0;
    int high = paragraphs.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final paragraph = paragraphs[mid];

      if (characterOffset < paragraph.startOffset) {
        high = mid - 1;
      } else if (characterOffset >= paragraph.endOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }

    // Offset didn't fall inside any paragraph (e.g. it landed exactly on
    // a separator between paragraphs). Clamping to the nearest valid
    // index is safer than throwing here — a highlight that's off by one
    // paragraph is a minor visual glitch; a crash mid-playback is not.
    return low.clamp(0, paragraphs.length - 1);
  }
}
