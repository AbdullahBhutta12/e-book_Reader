/// A saved reading position for one specific book, persisted across app
/// sessions so the user can pick up where they left off.
class ReadingProgress {
  const ReadingProgress({
    required this.bookPath,
    required this.characterOffset,
    required this.totalCharacters,
    required this.lastReadAt,
  });

  /// Identifies WHICH book this progress belongs to.
  ///
  /// This is `BookFile.identityKey`, NOT `BookFile.path` — despite the
  /// field name kept here for historical/API-shape reasons. `path` is
  /// NOT a valid book identity: on Android, `file_picker` re-copies a
  /// picked file into a freshly-named cache location on every single
  /// pick, so `path` for "the same book" is a different string almost
  /// every session. Using it as this key was the root cause of a bug
  /// where saved progress could never be found again on the next
  /// session — see `BookFile.identityKey`'s doc comment for the full
  /// explanation.
  final String bookPath;

  /// A GLOBAL offset into `BookContent.fullText` — the same offset space
  /// `BookReaderController.highlightRange`, `BookParagraph`, and
  /// `PlaybackChunk` all already share. This is deliberately a character
  /// offset, not a chunk index: `PlaybackChunker`'s chunk boundaries are
  /// an implementation detail of how text gets fed to the TTS engine, and
  /// could change (a different `maxChunkLength`, a future PDF/EPUB
  /// extractor) without invalidating previously-saved progress. Resuming
  /// means finding whichever chunk CURRENTLY contains this offset at
  /// resume time — see `BookReaderController._chunkIndexForOffset`.
  final int characterOffset;

  /// MODULE 8 ADDITION: the book's total extracted character count at
  /// the moment this was saved — i.e. `BookContent.fullText.length`.
  /// Added specifically so the Library screen can show a real progress
  /// PERCENTAGE per book without extracting every library book's full
  /// text just to count its characters (see the Module 8 architecture
  /// note on why that eager cost was rejected). `0` for entries saved
  /// before this field existed (`ReadingProgressStore.load` defaults a
  /// missing value to `0` rather than failing to parse) — see [fraction].
  final int totalCharacters;

  /// When this progress was last saved — shown to the user as part of
  /// deciding whether "resume" is even worth offering (see
  /// `BookReaderController`'s resume-prompt logic).
  final DateTime lastReadAt;

  /// How far through the book this position is, as a `0.0`–`1.0`
  /// fraction. `0` when [totalCharacters] is unknown (either genuinely
  /// `0`, or an entry saved before this field existed) — a book with no
  /// denominator has no meaningful percentage to show, and `0` is a safe,
  /// self-correcting display value rather than a divide-by-zero.
  double get fraction =>
      totalCharacters == 0 ? 0 : characterOffset / totalCharacters;
}
