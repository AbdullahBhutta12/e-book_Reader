/// One safely-sized piece of a book's text, handed to `TtsService.speak()`
/// in a single call.
///
/// WHY THIS EXISTS: Android's native TTS engine rejects any single
/// `speak()` request beyond a fixed character ceiling
/// (`TextToSpeech.getMaxSpeechInputLength()`, documented as 4000
/// characters) — real-device testing confirmed this fails outright for
/// an entire book (1,021,707 characters) sent in one call. A
/// `PlaybackChunk` is one piece of the book small enough to always be
/// accepted, in playback order.
///
/// WHY IT CARRIES [startOffset]/[endOffset] IN [BookContent.fullText]'s
/// GLOBAL OFFSET SPACE (the same space [BookParagraph] already uses):
/// This is what keeps the design ready for Module 5's word highlighting
/// without any further redesign. flutter_tts's word-boundary progress
/// callback reports an offset relative to whichever chunk is CURRENTLY
/// playing — a "local" offset. Adding `chunk.startOffset` to that local
/// offset immediately gives a book-wide position, which
/// `BookContent.paragraphIndexAt()` (built back in Module 3, specifically
/// anticipating this) already knows how to turn into "which paragraph is
/// this?" Chunk boundaries don't need to line up with paragraph
/// boundaries for this to work.
class PlaybackChunk {
  const PlaybackChunk({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  /// The exact text passed to `TtsService.speak()` for this chunk. This
  /// is always a real substring of `BookContent.fullText` — never text
  /// rebuilt by joining separate pieces back together — so it faithfully
  /// includes whatever's actually between its start and end (including
  /// the paragraph separators already present in `fullText`).
  final String text;

  /// Inclusive index into `BookContent.fullText` where this chunk begins.
  final int startOffset;

  /// Exclusive index into `BookContent.fullText` where this chunk ends.
  final int endOffset;
}
