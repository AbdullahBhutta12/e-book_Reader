import '../models/book_content.dart';
import '../models/playback_chunk.dart';

/// Splits a [BookContent] into a list of [PlaybackChunk]s, each small
/// enough for Android's native TTS engine to accept in one `speak()`
/// call.
///
/// WHY THIS LIVES IN `domain/services/`, AS A CONCRETE CLASS (not behind
/// an abstract interface like [TextExtractor], and not in `data/` like
/// [TtsService]):
/// This is pure Dart logic operating only on [BookContent] — no file
/// I/O, no platform channel, no third-party plugin. That makes it a
/// domain concern, not a data-layer one. And exactly like [TtsService],
/// there is only one chunking algorithm this app needs — an abstract
/// interface here would be abstraction with nothing behind it. It's
/// still fully unit-testable on its own: a test can hand it a small,
/// hand-built [BookContent] and assert on the resulting chunks, with no
/// device, plugin, or file system involved at all.
///
/// WHY PARAGRAPHS ARE THE STARTING POINT:
/// `BookContent.paragraphs` already exists — built by [PlainTextExtractor]
/// back in Module 3 specifically so something downstream could ask
/// "which paragraph is at offset X?" A paragraph boundary is also always
/// a safe, natural place to briefly pause between `speak()` calls, unlike
/// an arbitrary character cutoff that could land mid-sentence.
class PlaybackChunker {
  const PlaybackChunker({this.maxChunkLength = defaultMaxChunkLength});

  /// Half of Android's documented 4000-character `speak()` ceiling
  /// (`TextToSpeech.getMaxSpeechInputLength()`). The headroom below the
  /// hard limit accounts for OEM TTS engines that may enforce a slightly
  /// stricter real-world limit than the platform default, while keeping
  /// the pause between chunks short.
  static const int defaultMaxChunkLength = 2000;

  /// Never hardcoded elsewhere in this class — every size comparison
  /// below reads this field, so changing it (or overriding it via the
  /// constructor, e.g. in a test) changes the algorithm's behavior
  /// everywhere at once.
  final int maxChunkLength;

  /// Builds the full chunk list for [content], in playback order.
  ///
  /// CALLED EXACTLY ONCE PER BOOK: `BookReaderController` calls this a
  /// single time when a book's content finishes loading, and reuses the
  /// resulting list for every subsequent Play/Pause/Stop for that book —
  /// never recomputed on each Play press. See the controller for why
  /// that matters (state correctness, not just performance).
  List<PlaybackChunk> chunk(BookContent content) {
    // Step 1: expand every paragraph into one or more "pieces" — plain
    // (start, end) integer ranges into `content.fullText`, each
    // guaranteed to already fit within `maxChunkLength` on its own. Most
    // paragraphs produce exactly one piece; only oversized paragraphs
    // produce more than one. Nothing here allocates a new String yet —
    // this step is pure offset arithmetic plus pattern-matching on text
    // that's already resident in memory (`paragraph.text`).
    final List<({int start, int end})> pieces = [];
    for (final paragraph in content.paragraphs) {
      if (paragraph.text.length <= maxChunkLength) {
        pieces.add((start: paragraph.startOffset, end: paragraph.endOffset));
      } else {
        pieces.addAll(_splitOversizedParagraph(paragraph));
      }
    }

    // Step 2: greedily pack consecutive pieces together, without
    // exceeding `maxChunkLength`, so short paragraphs/sentences don't
    // each become their own separate `speak()` call — that would sound
    // choppy and multiply engine round-trip overhead for no benefit.
    final List<PlaybackChunk> chunks = [];
    int? packedStart;
    int packedEnd = 0;

    void flush() {
      final int? start = packedStart;
      if (start == null) return;
      // The ONLY place a String is actually materialized: one
      // `substring` call per finished chunk. We deliberately never
      // rebuild chunk text by re-joining individual piece strings — that
      // would be a second, redundant pass over data that already exists
      // as one contiguous block in `fullText`.
      chunks.add(
        PlaybackChunk(
          text: content.fullText.substring(start, packedEnd),
          startOffset: start,
          endOffset: packedEnd,
        ),
      );
      packedStart = null;
    }

    for (final piece in pieces) {
      if (piece.end <= piece.start) continue; // defensive: skip empty ranges

      final bool fitsInCurrentChunk = packedStart != null &&
          (piece.end - packedStart!) <= maxChunkLength;

      if (fitsInCurrentChunk) {
        packedEnd = piece.end;
      } else {
        flush();
        packedStart = piece.start;
        packedEnd = piece.end;
      }
    }
    flush();

    return chunks;
  }

  /// Splits ONE oversized paragraph into pieces that each fit within
  /// `maxChunkLength`, returned as global offsets (relative to
  /// `fullText`, via `paragraph.startOffset`).
  ///
  /// FALLBACK TIER 1 — sentence splitting: tried first, since a sentence
  /// boundary is a far less noticeable place for a brief pause than an
  /// arbitrary cutoff.
  List<({int start, int end})> _splitOversizedParagraph(
    BookParagraph paragraph,
  ) {
    final String text = paragraph.text;
    final int base = paragraph.startOffset;
    final List<({int start, int end})> result = [];

    for (final sentence in _sentenceRanges(text)) {
      if (sentence.end - sentence.start <= maxChunkLength) {
        result.add((start: base + sentence.start, end: base + sentence.end));
      } else {
        // FALLBACK TIER 2 — even a single sentence is pathologically
        // long (e.g. no punctuation for thousands of characters). Hard-
        // split it, but never mid-word.
        for (final piece in _hardSplit(text, sentence.start, sentence.end)) {
          result.add((start: base + piece.start, end: base + piece.end));
        }
      }
    }

    return result;
  }

  /// Splits [text] into sentence-shaped ranges by cutting AFTER
  /// sentence-ending punctuation and the whitespace that follows it.
  /// Because every cut lands on whitespace by construction, this can
  /// never split a word — the occasional early split after an
  /// abbreviation like "Mr." is an acceptable, purely cosmetic trade-off
  /// for a lightweight heuristic, not a word being broken.
  List<({int start, int end})> _sentenceRanges(String text) {
    final RegExp sentenceBoundary = RegExp(r'(?<=[.!?])\s+');
    final List<({int start, int end})> ranges = [];
    int start = 0;

    for (final RegExpMatch match in sentenceBoundary.allMatches(text)) {
      if (match.start > start) {
        ranges.add((start: start, end: match.start));
      }
      start = match.end;
    }
    if (start < text.length) {
      ranges.add((start: start, end: text.length));
    }

    return ranges;
  }

  /// Last-resort split for a span with no usable sentence boundaries at
  /// all. Always cuts on a whitespace character at or before the budget
  /// boundary — never mid-word — and additionally never inside a UTF-16
  /// surrogate pair (see [_avoidSurrogateSplit]). Only cuts mid-word in
  /// the genuinely pathological case where no whitespace exists anywhere
  /// in the entire remaining span — expected to never occur in a real
  /// book.
  List<({int start, int end})> _hardSplit(String text, int start, int end) {
    final List<({int start, int end})> ranges = [];
    int cursor = start;

    while (end - cursor > maxChunkLength) {
      final int splitAt =
          _findSplitIndex(text, cursor, cursor + maxChunkLength);
      ranges.add((start: cursor, end: splitAt));
      cursor = splitAt;
      // Skip the whitespace we just split on, so the next piece doesn't
      // start with a leading space.
      while (cursor < end && _isWhitespace(text.codeUnitAt(cursor))) {
        cursor++;
      }
    }

    if (cursor < end) {
      ranges.add((start: cursor, end: end));
    }

    return ranges;
  }

  /// Searches backward from [desiredIndex] for the nearest whitespace
  /// character, so the split never lands inside a word. Falls back to
  /// [desiredIndex] itself only if no whitespace exists anywhere between
  /// [cursor] and [desiredIndex].
  int _findSplitIndex(String text, int cursor, int desiredIndex) {
    for (int i = desiredIndex; i > cursor; i--) {
      if (_isWhitespace(text.codeUnitAt(i))) {
        return _avoidSurrogateSplit(text, i);
      }
    }
    return _avoidSurrogateSplit(text, desiredIndex);
  }

  /// Deliberately not exhaustive (no full Unicode whitespace table) —
  /// this only needs to catch the common cases well enough that a real
  /// book essentially never reaches the mid-word fallback. Missing an
  /// exotic Unicode space character just means the search continues
  /// further back (or, in the extreme case, falls through to the
  /// mid-word fallback), never a crash.
  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 || // space
        codeUnit == 0x09 || // tab
        codeUnit == 0x0A || // line feed
        codeUnit == 0x0D || // carriage return
        codeUnit == 0xA0; // non-breaking space
  }

  /// Dart strings are indexed in UTF-16 code units, not whole Unicode
  /// characters — a character outside the Basic Multilingual Plane
  /// (many emoji, some rarer CJK/mathematical characters) is stored as a
  /// "surrogate pair" of two code units. An arbitrary `substring` cut
  /// could otherwise land between the two halves of one such pair,
  /// corrupting it. This nudges the index left by one in that specific
  /// case. It does not attempt full grapheme-cluster awareness (e.g.
  /// combining accent marks) — that would need the separate
  /// `characters` package, which is more than this fallback path
  /// practically warrants.
  int _avoidSurrogateSplit(String text, int index) {
    if (index <= 0 || index >= text.length) return index;
    final int unit = text.codeUnitAt(index);
    final bool isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
    return isLowSurrogate ? index - 1 : index;
  }
}
