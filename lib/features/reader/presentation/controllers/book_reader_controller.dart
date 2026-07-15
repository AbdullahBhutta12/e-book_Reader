import 'package:flutter/foundation.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/text_extractor_factory.dart';
import '../../data/tts_service.dart';
import '../../domain/models/book_content_result.dart';
import '../../domain/models/book_file.dart';
import '../../domain/models/playback_chunk.dart';
import '../../domain/models/tts_init_result.dart';
import '../../domain/models/tts_playback_state.dart';
import '../../domain/services/playback_chunker.dart';

/// Owns the Reader screen's state: whether the book is loaded, whether
/// text-to-speech is ready, and (as of this patch) exactly which chunk of
/// the book is currently playing. Module 5 will extend this same class
/// with the currently-highlighted sentence/word, rather than introducing
/// a second, separate controller — exactly as planned in the
/// architecture review.
///
/// WHY `ChangeNotifier` (imported from `flutter/foundation.dart`, NOT
/// `flutter/material.dart`):
/// `ChangeNotifier` is a plain Dart change-notification mechanism — it
/// has nothing to do with Material Design widgets, so it lives in
/// Flutter's lower-level `foundation` library. Importing the narrower
/// `foundation.dart` here (instead of the much larger `material.dart`)
/// keeps this controller honest about what it actually depends on: this
/// class holds STATE, not UI.
///
/// WHY THIS IS SCOPED TO THE READER SCREEN (created when it opens,
/// destroyed when it closes) INSTEAD OF LIVING AT THE TRUE APP ROOT:
/// "Which book is open and how far did the TTS engine get reading it" is
/// only meaningful while a book is actually open. `provider`'s job here
/// is to share this state across the WIDGETS WITHIN the Reader screen —
/// the content view, and the playback control bar — not to make it
/// global.
///
/// ARCHITECTURE NOTE — this class is the middle layer of:
///   Presentation (ReaderScreen / PlaybackControlBar)
///         ↓ calls play() / pause() / stop()
///   BookReaderController        ← YOU ARE HERE
///         ↓ calls speak() / pause() / stop(), receives callbacks
///   TtsService
///         ↓ calls flutter_tts's platform channel
///   flutter_tts
/// Presentation never touches `TtsService` or `flutter_tts` directly —
/// it only ever calls methods on this controller and reads its exposed
/// state getters. `PlaybackChunker` is a third, sibling collaborator at
/// this same layer — a pure domain helper this controller calls, not
/// something `TtsService` or the presentation layer ever needs to know
/// about.
///
/// CHUNKED PLAYBACK — why this exists at all: real-device testing found
/// that sending an entire book (over 1,000,000 characters for a large
/// `.txt` file) to `TtsService.speak()` in one call fails outright —
/// Android's native TTS engine rejects any single request beyond a fixed
/// character ceiling. This controller now speaks the book one
/// [PlaybackChunk] at a time, automatically continuing to the next chunk
/// when the current one finishes, which from the user's perspective
/// sounds and behaves exactly like one continuous reading.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required BookFile book,
    TextExtractorFactory? extractorFactory,
    TtsService? ttsService,
    PlaybackChunker? chunker,
  })  : _book = book,
        _extractorFactory = extractorFactory ?? const TextExtractorFactory(),
        _ttsService = ttsService ?? TtsService(),
        _chunker = chunker ?? const PlaybackChunker() {
    // Must be called from the constructor BODY, not the initializer list
    // above — see the doc comment on `TtsService.attachHandlers` for why.
    _ttsService.attachHandlers(
      onStart: () => _setPlaybackState(TtsPlaybackState.playing),
      onContinue: () => _setPlaybackState(TtsPlaybackState.playing),
      onPause: () => _setPlaybackState(TtsPlaybackState.paused),
      onCompletion: _handleChunkCompletion,
      onCancel: () => _setPlaybackState(TtsPlaybackState.stopped),
      onError: _handleTtsError,
      onProgress: _handleProgress,
    );
    _loadContent();
    _initializeTts();
  }

  final BookFile _book;

  /// Injected via the constructor with a sensible default — same
  /// dependency-injection pattern used for `BookImportService` in
  /// `HomeScreen` back in Module 2, for the same reason: a test can
  /// supply a fake factory without touching the real file system.
  final TextExtractorFactory _extractorFactory;

  /// Same DI pattern again, one more time, for the TTS backend — a test
  /// can supply a fake `TtsService` without ever touching a real device
  /// TTS engine.
  final TtsService _ttsService;

  /// Same DI pattern a third time — a test can supply a `PlaybackChunker`
  /// with a small `maxChunkLength` to exercise the chunking/auto-advance
  /// logic without needing a real 1MB file.
  final PlaybackChunker _chunker;

  /// Guards every state mutation below against firing after this
  /// controller has been disposed. `dispose()` is synchronous, but this
  /// controller kicks off several independent async operations
  /// (`_loadContent`, `_initializeTts`, and every TTS callback) that can
  /// still be pending — or fire — after the Reader screen has already
  /// been popped and this controller torn down. Without this guard,
  /// `notifyListeners()` firing after `dispose()` throws a
  /// `FlutterError` ("A BookReaderController was used after being
  /// disposed").
  bool _disposed = false;

  /// `null` while the book is still loading. Once loading finishes, this
  /// is always one of [BookContentResult]'s subtypes — never null again
  /// after the first load completes.
  BookContentResult? _result;
  BookContentResult? get result => _result;

  bool get isLoading => _result == null;

  /// The book currently being read. Exposed so widgets (like the AppBar
  /// title, or the info sheet) can show its name/size/path without the
  /// Reader screen needing to hold a second reference to it separately.
  BookFile get book => _book;

  // --- Chunked playback ---------------------------------------------

  /// The full, pre-computed list of safe-to-speak chunks for this book.
  ///
  /// COMPUTED EXACTLY ONCE, in `_loadContent()`, when the book's content
  /// finishes loading — never recomputed here in `play()` or anywhere
  /// else. This matters for correctness, not just performance: if this
  /// were recomputed on every Play press, `_currentChunkIndex` (an index
  /// INTO this list) could silently end up pointing at a different piece
  /// of text than the one the user was actually mid-sentence through,
  /// especially once Module 5 starts tracking a highlighted position
  /// relative to a specific chunk.
  List<PlaybackChunk> _chunks = const [];

  /// Which chunk `play()` will speak next (or resume, mid-chunk, after a
  /// pause). Reset to `0` by `stop()`, by a fresh `_loadContent()`, and
  /// by a mid-playback error — in every one of those cases, the next
  /// Play press should start again from the beginning of the book.
  int _currentChunkIndex = 0;

  // --- Highlighting (Module 5) -----------------------------------------

  /// The book being spoken word currently, expressed in the SAME global
  /// offset space as `BookContent.fullText`/`BookParagraph`/
  /// `PlaybackChunk` — never in chunk-local offsets. `null` whenever
  /// nothing is actively being tracked (stopped, or before the first
  /// word of a session has been reported).
  ///
  /// WHY A RECORD INSTEAD OF TWO SEPARATE FIELDS: `start`/`end` are only
  /// ever meaningful together — there's no valid state where one exists
  /// without the other. A record makes "both or neither" the only
  /// representable shape, and gives `book_content_view.dart` a single
  /// value with built-in structural equality to key its `context.select`
  /// off, instead of two fields that could theoretically be read out of
  /// sync with each other.
  ///
  /// WHY THIS PRESERVES ITS LAST VALUE ACROSS A PAUSE (only cleared by
  /// `stop()`, a fresh chunk failing to start, or the book finishing):
  /// Leaving the last-spoken word highlighted while paused matches what
  /// the user sees on screen — "this is where you paused" — rather than
  /// the highlight vanishing and reappearing on resume for no reason.
  ({int start, int end})? _highlightRange;
  ({int start, int end})? get highlightRange => _highlightRange;

  /// The chunk-local offset that the CURRENT `speak()` call's progress
  /// events are relative to — added to every `_handleProgress` offset
  /// before adding `chunk.startOffset`, in addition to it (not instead
  /// of it).
  ///
  /// WHY THIS EXISTS — THE BUG THIS FIXES:
  /// `TtsService.pause()` documents that Android's flutter_tts pause
  /// workaround has no native pause at all: it remembers the last
  /// `onRangeStart` offset, and on the NEXT `speak()` call (a resume),
  /// it internally slices the text from that remembered offset before
  /// re-synthesizing — see that doc comment for the full explanation.
  /// The progress events flutter_tts reports for THAT resumed
  /// `speak()` call are offsets into the RESUMED SLICE, starting back
  /// near zero — not offsets into the original chunk. Simply adding
  /// `chunk.startOffset` to them (as if every `speak()` call always
  /// started at the chunk's beginning) therefore snapped the highlight
  /// back to the start of the chunk on every resume, even though audio
  /// correctly kept playing from the paused position. This field is
  /// the missing piece: it's the local offset (within the chunk) that
  /// the in-flight `speak()` call actually started from — `0` for a
  /// fresh chunk, or the paused-at offset for a resumed one — so
  /// `_handleProgress` can re-base the resumed slice's own offsets back
  /// into the chunk's own local space before adding `chunk.startOffset`.
  int _chunkProgressBase = 0;

  /// The most recent chunk-local offset reported by `_handleProgress`
  /// for the chunk currently in flight — i.e. `_chunkProgressBase +`
  /// the last raw `localStart` flutter_tts reported. This is exactly
  /// the offset Android's own pause workaround remembers internally
  /// (see `_chunkProgressBase`'s doc comment), so reading it back here
  /// when `play()` resumes a paused chunk gives the next `speak()`
  /// call's progress events the correct base to re-align against.
  /// `null` whenever no progress event has landed yet for the chunk
  /// currently in flight (e.g. paused before speech audibly started).
  int? _lastChunkLocalOffset;

  // --- Text-to-speech state -------------------------------------------

  TtsPlaybackState _playbackState = TtsPlaybackState.stopped;
  TtsPlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == TtsPlaybackState.playing;
  bool get isPaused => _playbackState == TtsPlaybackState.paused;

  /// `true` once `TtsService.initialize()` has completed AND succeeded.
  bool _isTtsReady = false;
  bool get isTtsReady => _isTtsReady;

  /// A persistent reason TTS can't be used AT ALL right now (no engine,
  /// missing language, or an unexpected init failure). Non-null for the
  /// rest of this controller's lifetime once set — unlike
  /// [ttsErrorMessage] below, there's nothing transient about "this
  /// device has no TTS engine installed."
  String? _ttsUnavailableReason;
  String? get ttsUnavailableReason => _ttsUnavailableReason;

  /// `true` only during the brief window before initialization has
  /// concluded either way. The UI uses this to show a small loading
  /// indicator instead of either the control bar or an error, rather
  /// than the bar popping in a beat after the screen first appears.
  bool get isTtsInitializing => !_isTtsReady && _ttsUnavailableReason == null;

  /// A one-off, transient error — e.g. the engine failed mid-sentence.
  /// The UI shows this once (as a SnackBar) then calls [clearTtsError].
  /// This is DIFFERENT from [ttsUnavailableReason]: that's a standing
  /// condition shown inline for as long as it's true; this is a single
  /// past event that should disappear once acknowledged.
  String? _ttsErrorMessage;
  String? get ttsErrorMessage => _ttsErrorMessage;

  Future<void> _loadContent() async {
    // STABILITY PATCH: this used to start with a
    // `SupportedBookFormat.fromExtension(_book.extension)` call and a
    // defensive `if (format == null)` branch. Now that `BookFile.format`
    // is itself a `SupportedBookFormat`, that branch is impossible, so
    // there's nothing left to defend against here.
    final extractor = _extractorFactory.extractorFor(_book.format);
    if (extractor == null) {
      _finishContentWith(BookContentNotYetReadable(_book.format));
      return;
    }

    try {
      final content = await extractor.extract(_book);
      // Computed exactly ONCE, right here — see `_chunks`' own doc
      // comment for why reusing this same list for the book's whole
      // lifetime (rather than recomputing it in `play()`) matters for
      // correctness, not just performance.
      _chunks = _chunker.chunk(content);
      _finishContentWith(BookContentLoaded(content));
    } catch (_) {
      // We deliberately don't surface the raw exception message to the
      // user — it's typically a low-level I/O error that means nothing
      // to someone who isn't a developer. A clear, honest, generic
      // message serves them better than a stack trace fragment.
      _finishContentWith(
        const BookContentLoadFailure(AppStrings.readerLoadFailureMessage),
      );
    }
  }

  Future<void> _initializeTts() async {
    final TtsInitResult initResult = await _ttsService.initialize();

    // Exhaustive switch (Dart 3) — same pattern used for BookImportResult
    // and BookContentResult. Every TtsInitResult subtype maps to exactly
    // one outcome here; adding a fifth subtype later without handling it
    // here would fail to compile, not fail silently at runtime.
    switch (initResult) {
      case TtsInitSuccess():
        _isTtsReady = true;
      case TtsInitUnavailable():
        _isTtsReady = false;
        _ttsUnavailableReason = AppStrings.ttsUnavailableMessage;
      case TtsInitUnsupportedLanguage(:final languageCode):
        _isTtsReady = false;
        _ttsUnavailableReason =
            AppStrings.ttsUnsupportedLanguageMessage(languageCode);
      case TtsInitFailure():
        _isTtsReady = false;
        _ttsUnavailableReason = AppStrings.ttsInitGenericError;
    }

    _notify();
  }

  /// Starts reading the book aloud from the beginning, or resumes it if
  /// currently paused, or continues from wherever auto-advance last left
  /// off — all three cases are covered by the SAME line
  /// (`_speakCurrentChunk`), because `_currentChunkIndex` already points
  /// at the right place in every one of them.
  Future<void> play() async {
    // Guards, each corresponding to one of the "prevent invalid states"
    // rules: don't double-play, don't play before TTS is ready. The
    // control bar's UI already disables the Play button in both cases —
    // this is a deliberate second line of defense, matching the same
    // defense-in-depth pattern used for `HomeScreen`'s import flow in the
    // stability patch.
    if (!_isTtsReady) return;
    if (_playbackState == TtsPlaybackState.playing) return;

    // `_chunks` is only ever non-empty once content has loaded
    // successfully AND produced at least one chunk — so this single
    // check now correctly covers "still loading," "failed to load," AND
    // "loaded but genuinely empty," subsuming what used to be a separate
    // `contentResult is! BookContentLoaded` check.
    if (_chunks.isEmpty) return;

    // Establish what the upcoming `speak()` call's progress offsets will
    // be relative to, BEFORE calling it — `_handleProgress` needs this
    // decided ahead of time, not inferred afterward.
    //
    // RESUMING A PAUSED CHUNK: flutter_tts is about to internally slice
    // the text from wherever it remembers pausing (see
    // `_chunkProgressBase`'s doc comment) — the same position this
    // controller was already tracking as `_lastChunkLocalOffset`. Using
    // that as the new base is what keeps the highlight continuous
    // instead of snapping back to the chunk's start.
    //
    // ANYTHING ELSE (fresh chunk, whether the very first Play or an
    // auto-advance): the upcoming `speak()` call gets the chunk's full,
    // untouched text, so its progress offsets are already relative to
    // the chunk's own start — base `0`, nothing to carry over.
    if (_playbackState == TtsPlaybackState.paused) {
      _chunkProgressBase = _lastChunkLocalOffset ?? 0;
    } else {
      _chunkProgressBase = 0;
      _lastChunkLocalOffset = null;
    }

    await _speakCurrentChunk();
  }

  Future<void> pause() async {
    if (_playbackState != TtsPlaybackState.playing) return;
    // Pauses whatever chunk is currently mid-speech; `_currentChunkIndex`
    // doesn't move. flutter_tts's own Android pause/resume mechanism
    // (see `TtsService.pause()`) keeps working exactly as before, since
    // each chunk is still just one ordinary `speak()` call from its
    // point of view.
    await _ttsService.pause();
  }

  Future<void> stop() async {
    if (_playbackState == TtsPlaybackState.stopped) return;

    // Set state and reset the chunk index SYNCHRONOUSLY, before awaiting
    // the native stop call below. This closes a real race: if a chunk
    // finishes naturally at almost the same instant the user presses
    // Stop, `_handleChunkCompletion` could otherwise fire during this
    // `await` and incorrectly auto-advance into the next chunk. Setting
    // this first means that method's own guard always sees `.stopped`
    // in that race, and does nothing.
    _currentChunkIndex = 0;
    // A fresh Play after Stop starts over from the beginning of the
    // book, not from wherever the highlight last was — so the highlight
    // shouldn't linger either. `_setPlaybackState` above already
    // notifies listeners for the state change; clearing this first means
    // that same notification also carries the cleared highlight, rather
    // than needing a second `_notify()` call just for this field.
    _highlightRange = null;
    _chunkProgressBase = 0;
    _lastChunkLocalOffset = null;
    _setPlaybackState(TtsPlaybackState.stopped);

    await _ttsService.stop();
  }

  /// Called by the UI immediately after showing [ttsErrorMessage] once.
  void clearTtsError() {
    if (_ttsErrorMessage == null) return; // avoid a no-op rebuild
    _ttsErrorMessage = null;
    _notify();
  }

  /// Speaks whatever chunk `_currentChunkIndex` currently points at.
  /// Used by [play] (fresh start / resume) and by [_handleChunkCompletion]
  /// (auto-advance) — both cases are "speak the chunk the index already
  /// points at," so there's exactly one method that does that.
  Future<void> _speakCurrentChunk() async {
    if (_currentChunkIndex >= _chunks.length) return; // defensive

    final bool started =
        await _ttsService.speak(_chunks[_currentChunkIndex].text);

    // If the platform rejected the request outright, there's no
    // `onStart`/`onError` callback coming to tell us that — we have to
    // report the failure ourselves right here.
    if (!started) {
      _handleTtsError(AppStrings.ttsPlaybackErrorMessage);
    }
  }

  /// Fires when one chunk finishes speaking naturally. Either advances
  /// to the next chunk and keeps going (auto-advance — the whole point
  /// of this patch), or, if that was the last chunk, resets to the
  /// beginning and stops.
  void _handleChunkCompletion() {
    // If `stop()` already reset state to `.stopped` (see its own comment
    // for the race this guards against), this callback must NOT
    // auto-advance into whatever chunk index was left behind.
    if (_playbackState != TtsPlaybackState.playing) return;

    final int nextIndex = _currentChunkIndex + 1;
    if (nextIndex < _chunks.length) {
      _currentChunkIndex = nextIndex;
      // A new chunk's `speak()` call always gets its full, untouched
      // text — never a resumed slice — so its progress offsets are
      // relative to its own start. Same reasoning as the fresh-start
      // branch in `play()`.
      _chunkProgressBase = 0;
      _lastChunkLocalOffset = null;
      // Fire-and-forget: flutter_tts's completion handler is a
      // synchronous `void Function()`, so it can't be awaited here. The
      // next chunk's own `onStart`/`onError` callbacks report what
      // happens, exactly like every other TTS call this controller
      // makes.
      _speakCurrentChunk();
    } else {
      _currentChunkIndex = 0;
      // The book has genuinely finished — same reasoning as `stop()`:
      // nothing should still look "highlighted" once playback is over.
      _highlightRange = null;
      _chunkProgressBase = 0;
      _lastChunkLocalOffset = null;
      _setPlaybackState(TtsPlaybackState.stopped);
    }
  }

  void _handleTtsError(String message) {
    _ttsErrorMessage = message;
    _playbackState = TtsPlaybackState.stopped;
    // A mid-book error halts entirely rather than trying to skip or
    // retry the failing chunk — the simplest honest behavior for a rare
    // case, and consistent with not adding complexity that isn't earned
    // yet. The next Play press starts over from the beginning.
    _currentChunkIndex = 0;
    _highlightRange = null;
    _chunkProgressBase = 0;
    _lastChunkLocalOffset = null;
    _notify();
  }

  /// Translates one word-boundary event — reported by `TtsService` in
  /// offsets LOCAL to whichever chunk is currently speaking — into a
  /// book-wide `[start, end)` range, and republishes it as
  /// `highlightRange`.
  ///
  /// WHY `_currentChunkIndex` IS THE RIGHT CHUNK TO ADD ITS
  /// `startOffset` TO: this callback only ever fires while `TtsService`
  /// is actively speaking text that came from `_speakCurrentChunk`,
  /// which always sends `_chunks[_currentChunkIndex].text` — so the
  /// chunk this progress event is reporting on and the chunk
  /// `_currentChunkIndex` currently points at are always the same one,
  /// with no separate bookkeeping required to keep them in sync.
  ///
  /// WHY THIS GUARDS AGAINST A STALE/OUT-OF-RANGE INDEX: chunk auto-
  /// advance and this progress callback both originate from
  /// `flutter_tts`'s platform channel, arriving asynchronously — a
  /// straggling progress event from a chunk that has already finished
  /// (or from just after `stop()` reset the index to `0`) is a real,
  /// if rare, possibility. Bailing out silently here is the same
  /// "a stale highlight is a minor visual glitch, not worth a crash"
  /// tradeoff `BookContent.paragraphIndexAt` already makes for offsets
  /// that don't land cleanly.
  void _handleProgress(String word, int localStart, int localEnd) {
    if (_currentChunkIndex >= _chunks.length) return;
    if (localEnd <= localStart) return;

    final PlaybackChunk chunk = _chunks[_currentChunkIndex];

    // THE FIX: `localStart`/`localEnd` are relative to whatever text was
    // actually just handed to `speak()` for the CURRENT call — which,
    // per `_chunkProgressBase`'s doc comment, is the full chunk on a
    // fresh start (base `0`) but only a RESUMED SLICE of it after a
    // pause (base = wherever it was paused). Re-basing into the chunk's
    // own local space first, THEN adding `chunk.startOffset`, is what
    // keeps this correct in both cases instead of only the fresh-start
    // one.
    final int chunkLocalStart = _chunkProgressBase + localStart;
    final int chunkLocalEnd = _chunkProgressBase + localEnd;

    // Remembered so a SUBSEQUENT pause->resume on this same chunk has
    // the right base to re-align against — see `play()`.
    _lastChunkLocalOffset = chunkLocalStart;

    final int globalStart = chunk.startOffset + chunkLocalStart;
    final int globalEnd = chunk.startOffset + chunkLocalEnd;

    _highlightRange = (start: globalStart, end: globalEnd);
    _notify();
  }

  /// Every playback-state transition funnels through here so the
  /// "avoid unnecessary rebuilds" rule is enforced in exactly one place,
  /// instead of every call site remembering to check it individually.
  void _setPlaybackState(TtsPlaybackState next) {
    if (_playbackState == next) return;
    _playbackState = next;
    _notify();
  }

  void _finishContentWith(BookContentResult result) {
    _result = result;
    _notify();
  }

  /// Every `notifyListeners()` call in this class goes through here — the
  /// one place that enforces the "never notify after dispose" rule.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Fire-and-forget: dispose() is synchronous and can't be awaited, but
    // we still want the native engine told to stop rather than left
    // reading a book whose screen just closed.
    _ttsService.stop();
    super.dispose();
  }
}
