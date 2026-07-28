import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import '../../../../core/constants/app_strings.dart';
import '../../data/reading_progress_store.dart';
import '../../data/text_extractor_factory.dart';
import '../../data/tts_service.dart';
import '../../data/tts_settings_store.dart';
import '../../domain/models/book_content_result.dart';
import '../../domain/models/book_file.dart';
import '../../domain/models/playback_chunk.dart';
import '../../domain/models/reading_progress.dart';
import '../../domain/models/tts_init_result.dart';
import '../../domain/models/tts_playback_state.dart';
import '../../domain/models/tts_settings.dart';
import '../../domain/services/playback_chunker.dart';

/// Owns the Reader screen's state: whether the book is loaded, whether
/// text-to-speech is ready, exactly which chunk of the book is currently
/// playing, the currently-highlighted word (Module 5), and — as of
/// Module 6 — how far into the book the user has read, persisted across
/// app sessions.
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
/// MODULE 6 NOTE ON THE ONE NEW IMPORT (`flutter/widgets.dart`, narrowed
/// to exactly `WidgetsBinding`/`WidgetsBindingObserver`/
/// `AppLifecycleState`): detecting "the app was backgrounded" (one of
/// this module's required save triggers) has no `foundation`-level
/// equivalent — `WidgetsBindingObserver` is Flutter's standard,
/// lowest-level mechanism for it, and is a lifecycle-observation
/// interface, not a widget. This is still far short of pulling in
/// `material.dart` — the principle above ("this class holds state, not
/// UI") is about not depending on Material widgets, which this doesn't.
///
/// WHY THIS IS SCOPED TO THE READER SCREEN (created when it opens,
/// destroyed when it closes) INSTEAD OF LIVING AT THE TRUE APP ROOT:
/// "Which book is open and how far did the TTS engine get reading it" is
/// only meaningful while a book is actually open. `provider`'s job here
/// is to share this state across the WIDGETS WITHIN the Reader screen —
/// not to make it global.
///
/// ARCHITECTURE NOTE — this class is the middle layer of:
///   Presentation (ReaderScreen / PlaybackControlBar)
///         ↓ calls play() / pause() / stop() / resumeFromSaved() / etc.
///   BookReaderController        ← YOU ARE HERE
///         ↓ calls TtsService (speak/pause/stop, callbacks) and
///           ReadingProgressStore (save/load/clear)
///   TtsService                          ReadingProgressStore
///         ↓                                   ↓
///   flutter_tts                        shared_preferences
/// Presentation never touches `TtsService`, `ReadingProgressStore`, or
/// any third-party package directly — it only ever calls methods on this
/// controller and reads its exposed state getters.
class BookReaderController extends ChangeNotifier with WidgetsBindingObserver {
  BookReaderController({
    required BookFile book,
    TextExtractorFactory? extractorFactory,
    TtsService? ttsService,
    PlaybackChunker? chunker,
    ReadingProgressStore? progressStore,
    TtsSettingsStore? settingsStore,
  })  : _book = book,
        _extractorFactory = extractorFactory ?? const TextExtractorFactory(),
        _ttsService = ttsService ?? TtsService(),
        _chunker = chunker ?? const PlaybackChunker(),
        _progressStore = progressStore ?? ReadingProgressStore(),
        _settingsStore = settingsStore ?? TtsSettingsStore() {
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
    // Registers this controller to hear `AppLifecycleState` changes (see
    // `didChangeAppLifecycleState` below) — the "backgrounding" save
    // trigger Module 6 requires. Paired with `removeObserver` in
    // `dispose()`.
    WidgetsBinding.instance.addObserver(this);
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

  /// Same DI pattern a fourth time — a test can supply a fake
  /// `ReadingProgressStore` without touching real device storage.
  final ReadingProgressStore _progressStore;

  /// Same DI pattern a fifth time (Module 7) — a test can supply a fake
  /// `TtsSettingsStore` the same way.
  final TtsSettingsStore _settingsStore;

  /// Guards every state mutation below against firing after this
  /// controller has been disposed. `dispose()` is synchronous, but this
  /// controller kicks off several independent async operations that can
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
  /// of text than the one the user was actually mid-sentence through.
  List<PlaybackChunk> _chunks = const [];

  /// Which chunk `play()` will speak next (or resume, mid-chunk, after a
  /// pause). Reset to `0` by `stop()`, by a fresh `_loadContent()`, by a
  /// mid-playback error, and set to a specific chunk by
  /// `resumeFromSaved()` — in the first three cases, the next Play press
  /// should start again from the beginning of the book; in the fourth,
  /// from wherever the user chose to resume.
  int _currentChunkIndex = 0;

  /// Total characters in this book's extracted text — the denominator
  /// for `progressFraction`. `0` until content finishes loading.
  int _totalCharacters = 0;

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

  /// Set by `resumeFromSaved`, consumed by the very next
  /// `_speakCurrentChunk` call: how far INTO `_chunks[_currentChunkIndex]`'s
  /// OWN text the saved offset actually landed.
  ///
  /// ROOT CAUSE THIS FIXES — "chunk-level resume" was never actually
  /// applied within the chunk at all: `resumeFromSaved` correctly picked
  /// out the right CHUNK (`_currentChunkIndex` was always correct — this
  /// was verified by direct tracing/logging), but the next `play()` ->
  /// `_speakCurrentChunk()` always spoke `_chunks[_currentChunkIndex]`'s
  /// text FROM ITS OWN START, exactly like a brand-new chunk, because
  /// nothing recorded WHERE inside that chunk the saved offset actually
  /// was. For a book big enough to have many small chunks, that's a
  /// bounded (if imprecise) few-thousand-character rewind — easy to
  /// mistake for "basically working." For a SHORT book (or the specific
  /// file used in on-device testing here) that fits in a single chunk,
  /// "the start of the containing chunk" and "the very start of the
  /// book" are the EXACT SAME position — so playback and highlighting
  /// visibly restarted from page one every time, while the on-screen
  /// scroll (computed independently, as a plain fraction of the whole
  /// book — see `pendingScrollFraction`) correctly jumped ahead, making
  /// it look like only the TTS side was broken.
  ///
  /// THE FIX: this field carries the missing "how far into the chunk"
  /// number forward from `resumeFromSaved` to the next `play()` call,
  /// which slices the chunk's text before ever handing it to
  /// `TtsService.speak()` — the exact same "start `speak()` partway
  /// through a chunk's text, then re-base `_handleProgress`'s offsets by
  /// this same amount" technique `_chunkProgressBase`/
  /// `_lastChunkLocalOffset` already use for an ordinary in-session
  /// pause/resume, above. This is genuinely the SAME kind of resume —
  /// "continue this chunk from partway through," not "start this chunk
  /// over" — just triggered by a saved cross-session offset instead of a
  /// live pause.
  ///
  /// `null` whenever there's nothing pending — i.e. every `play()` call
  /// that ISN'T the very next one after `resumeFromSaved` — so an
  /// ordinary fresh start or auto-advance is never affected by this.
  int? _pendingResumeLocalOffset;

  // --- Reading progress & resume (Module 6) -----------------------------

  /// A GLOBAL offset the user was last known to be reading at — unlike
  /// [_highlightRange], this is NEVER cleared by `stop()`. It exists
  /// specifically so [progressFraction] (and progress saving) has a
  /// stable, durable answer to "how far into the book is the user?" even
  /// after playback stops, whereas [_highlightRange] is specifically
  /// about "what word should be visually highlighted RIGHT NOW" — two
  /// genuinely different questions that happened to share one field
  /// before this module needed to tell them apart.
  int _lastKnownOffset = 0;

  /// Non-null exactly when a previous session's saved progress exists
  /// for this book AND hasn't been resolved yet (by [resumeFromSaved] or
  /// [dismissResumePrompt]) in this session. The Reader screen shows a
  /// resume-or-start-over prompt for as long as this is non-null.
  int? _pendingResumeOffset;
  int? get pendingResumeOffset => _pendingResumeOffset;

  /// Set exactly once, by [resumeFromSaved], to the fraction (`0.0`–`1.0`)
  /// through the book the user's saved position was at — the ONLY signal
  /// `BookContentView` (the on-screen scrollable text) has that it should
  /// jump forward past the very beginning instead of opening at its
  /// default scroll position.
  ///
  /// WHY THIS IS THE ROOT CAUSE OF "the book still opens from the
  /// beginning" EVEN AFTER TAPPING RESUME: [resumeFromSaved] already
  /// correctly restores [_currentChunkIndex] (so a subsequent Play press
  /// correctly starts speaking — and highlighting — from the resumed
  /// chunk, not chunk `0`). But nothing previously told the READING VIEW
  /// itself to scroll anywhere — `BookContentView` had no concept of a
  /// resume position at all, so its `ListView` always rendered at its
  /// default (top) scroll offset regardless of `_currentChunkIndex`. From
  /// the user's perspective — looking at the screen, not necessarily
  /// listening yet — that reads as "resume did nothing."
  ///
  /// WHY A FRACTION, NOT A PIXEL OFFSET: this controller has no idea how
  /// tall any given paragraph renders on screen (font size, screen width,
  /// and accessibility text scaling all affect that, and none of them are
  /// this class's concern). A proportional fraction through the book's
  /// total character count is the same "good enough, chunk/paragraph-
  /// level precision, not exact-pixel precision" tradeoff this module
  /// already makes for chunk-level (not word-level) resume — see
  /// `_chunkIndexForOffset`'s own doc comment for that same reasoning.
  /// `BookContentView` turns this fraction into a concrete scroll offset
  /// once its `ListView` has actually laid out and knows its real
  /// `maxScrollExtent`.
  ///
  /// `null` before a resume happens, and again immediately after
  /// `BookContentView` has consumed it (see [consumePendingScroll]) — so
  /// it can never fire a second time and re-snap the view away from
  /// wherever the user has since scrolled to.
  double? _pendingScrollFraction;
  double? get pendingScrollFraction => _pendingScrollFraction;

  /// How far through the book [_lastKnownOffset] currently is, as a
  /// `0.0`–`1.0` fraction — the basis for the Reader screen's progress
  /// indicator. `0` before content has finished loading (division by a
  /// still-zero [_totalCharacters] would otherwise be undefined).
  double get progressFraction =>
      _totalCharacters == 0 ? 0 : _lastKnownOffset / _totalCharacters;

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

  // --- Playback settings (Module 7) --------------------------------------

  /// The user's current speech-rate preference — starts at
  /// `TtsService.defaultSpeechRate` and is overwritten, once, by whatever
  /// was previously saved (see `_initializeTts`) as soon as that load
  /// completes, before the settings UI can ever be shown.
  double _speechRate = TtsService.defaultSpeechRate;
  double get speechRate => _speechRate;

  double _pitch = TtsService.defaultPitch;
  double get pitch => _pitch;

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
      _totalCharacters = content.fullText.length;

      // MODULE 6: check for saved progress from a previous session, now
      // that we know how long this book actually is (needed to sanity-
      // check the saved offset below).
      final ReadingProgress? saved =
          await _progressStore.load(_book.identityKey);
      if (saved != null &&
          saved.characterOffset > 0 &&
          saved.characterOffset < _totalCharacters) {
        _pendingResumeOffset = saved.characterOffset;
        _lastKnownOffset = saved.characterOffset;
      }

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
        // MODULE 7: apply whatever rate/pitch the user last saved, if
        // anything — done here (once, right after a successful init)
        // rather than inside `TtsService.initialize()` itself, so that
        // class stays focused purely on "is the engine usable," with no
        // knowledge of settings persistence at all.
        final TtsSettings? savedSettings = await _settingsStore.load();
        if (savedSettings != null) {
          _speechRate = savedSettings.speechRate;
          _pitch = savedSettings.pitch;
          await _ttsService.setSpeechRate(_speechRate);
          await _ttsService.setPitch(_pitch);
        }
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
  /// currently paused, or continues from wherever auto-advance (or a
  /// resumed session) last left off — all covered by the SAME line
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
    // ANYTHING ELSE (fresh chunk — the very first Play, an auto-advance,
    // or a chunk selected by `resumeFromSaved`): the upcoming `speak()`
    // call gets the chunk's full, untouched text, so its progress
    // offsets are already relative to the chunk's own start — base `0`,
    // nothing to carry over.
    //
    // UNLESS `resumeFromSaved` left a pending within-chunk offset (see
    // `_pendingResumeLocalOffset`'s doc comment) — consumed here, exactly
    // once, by capturing it into a local BEFORE clearing the field, so a
    // later auto-advance into the NEXT chunk is never affected by it.
    final int resumeLocalOffset = _pendingResumeLocalOffset ?? 0;
    _pendingResumeLocalOffset = null;

    if (_playbackState == TtsPlaybackState.paused) {
      _chunkProgressBase = _lastChunkLocalOffset ?? 0;
    } else {
      _chunkProgressBase = resumeLocalOffset;
      _lastChunkLocalOffset = null;
    }

    await _speakCurrentChunk(seekOffset: resumeLocalOffset);
  }

  Future<void> pause() async {
    if (_playbackState != TtsPlaybackState.playing) return;
    // Pauses whatever chunk is currently mid-speech; `_currentChunkIndex`
    // doesn't move. flutter_tts's own Android pause/resume mechanism
    // (see `TtsService.pause()`) keeps working exactly as before, since
    // each chunk is still just one ordinary `speak()` call from its
    // point of view.
    await _ttsService.pause();
    // MODULE 6: pause is one of the three required save triggers
    // (pause/stop/backgrounding). Fire-and-forget is deliberate here —
    // the user doesn't need to wait on a disk write to see the Pause
    // button respond.
    _saveProgress();
  }

  Future<void> stop() async {
    if (_playbackState == TtsPlaybackState.stopped) return;

    // MODULE 6: capture and save progress BEFORE resetting any state
    // below — `_lastKnownOffset` reflects "where the user was" right up
    // until this point; saving it here (rather than after `_stop`
    // resets things) is what lets a Stop mid-book still offer a resume
    // prompt next time this book is opened, matching this module's own
    // "persist on stop" requirement.
    _saveProgress();

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

  /// Called by the settings sheet's rate slider as the user drags it.
  /// Applies the new rate to the engine immediately (audible even
  /// mid-book — see `TtsService.setSpeechRate`) and persists it so it's
  /// still in effect the next time ANY book is opened, not just this
  /// one.
  Future<void> setSpeechRate(double rate) async {
    if (_speechRate == rate) return; // avoid a no-op rebuild
    _speechRate = rate;
    _notify();
    await _ttsService.setSpeechRate(rate);
    // Fire-and-forget, same reasoning as `_saveProgress`: the slider
    // shouldn't wait on a disk write to feel responsive.
    _settingsStore.save(TtsSettings(speechRate: _speechRate, pitch: _pitch));
  }

  /// Same shape as [setSpeechRate], for pitch.
  Future<void> setPitch(double pitch) async {
    if (_pitch == pitch) return; // avoid a no-op rebuild
    _pitch = pitch;
    _notify();
    await _ttsService.setPitch(pitch);
    _settingsStore.save(TtsSettings(speechRate: _speechRate, pitch: _pitch));
  }

  /// Called by the UI when the user chooses "Resume" on the resume
  /// prompt. Points playback at whichever chunk currently contains the
  /// saved offset — see `_chunkIndexForOffset` for why a chunk-level
  /// resume, not a mid-chunk one, is the right precision to promise
  /// across app restarts. Also records [pendingScrollFraction] so the
  /// on-screen reading view can jump forward to roughly that position
  /// too, instead of silently staying at the top of the book — see that
  /// field's own doc comment for why this was the missing piece.
  void resumeFromSaved() {
    final int? offset = _pendingResumeOffset;
    if (offset == null) return;
    _currentChunkIndex = _chunkIndexForOffset(offset);
    // THE ACTUAL FIX: how far PAST this chunk's own start the saved
    // offset was — see `_pendingResumeLocalOffset`'s doc comment for why
    // this (not just picking the right chunk) is what was missing.
    // Clamped defensively: `chunk.startOffset` and `offset` are already
    // guaranteed consistent by `_chunkIndexForOffset`, but a slice index
    // must never be allowed to exceed the chunk text's own length.
    final PlaybackChunk resumedChunk = _chunks[_currentChunkIndex];
    _pendingResumeLocalOffset = (offset - resumedChunk.startOffset).clamp(
      0,
      resumedChunk.text.length,
    );
    _pendingScrollFraction =
        _totalCharacters == 0 ? null : offset / _totalCharacters;
    _pendingResumeOffset = null;
    _notify();
  }

  /// Called by `BookContentView` immediately after it has scrolled to
  /// [pendingScrollFraction] once — the same "consume a one-off signal,
  /// then clear it" pattern `clearTtsError` uses above, so this can never
  /// fire a second time and yank the view back to the resume point after
  /// the user has since scrolled elsewhere themselves.
  void consumePendingScroll() {
    if (_pendingScrollFraction == null) return; // avoid a no-op rebuild
    _pendingScrollFraction = null;
    _notify();
  }

  /// Called by the UI when the user chooses "Start Over" on the resume
  /// prompt. Leaves `_currentChunkIndex` at its default (`0`) and clears
  /// the previously-saved progress from storage — without this, closing
  /// and reopening this same book again soon after would show the exact
  /// same stale resume prompt the user just dismissed.
  void dismissResumePrompt() {
    if (_pendingResumeOffset == null) return;
    _pendingResumeOffset = null;
    _progressStore.clear(_book.identityKey); // fire-and-forget
    _notify();
  }

  /// Speaks whatever chunk `_currentChunkIndex` currently points at —
  /// from that chunk's own start, unless [seekOffset] says otherwise.
  /// Used by [play] (fresh start / cross-session resume) and by
  /// [_handleChunkCompletion] (auto-advance, always `seekOffset: 0`) —
  /// every case is "speak the chunk the index already points at, from
  /// some point within it," so there's exactly one method that does
  /// that.
  ///
  /// WHY [seekOffset] EXISTS — see `_pendingResumeLocalOffset`'s doc
  /// comment for the full root-cause story: picking the right CHUNK was
  /// never the missing piece; picking the right point WITHIN it was.
  /// Without this, every resume — no matter how correctly
  /// `_currentChunkIndex` was restored — spoke that chunk's text from
  /// its own beginning, which is indistinguishable from "the beginning
  /// of the book" whenever that chunk happens to BE most or all of the
  /// book (a short book, or simply the first chunk).
  Future<void> _speakCurrentChunk({int seekOffset = 0}) async {
    if (_currentChunkIndex >= _chunks.length) return; // defensive

    final PlaybackChunk chunk = _chunks[_currentChunkIndex];
    final String textToSpeak =
        (seekOffset > 0 && seekOffset < chunk.text.length)
        ? chunk.text.substring(seekOffset)
        : chunk.text;

    final bool started = await _ttsService.speak(textToSpeak);

    // If the platform rejected the request outright, there's no
    // `onStart`/`onError` callback coming to tell us that — we have to
    // report the failure ourselves right here.
    if (!started) {
      _handleTtsError(AppStrings.ttsPlaybackErrorMessage);
    }
  }

  /// Fires when one chunk finishes speaking naturally. Either advances
  /// to the next chunk and keeps going (auto-advance), or, if that was
  /// the last chunk, resets to the beginning, stops, and clears any
  /// saved progress — the book is genuinely finished, so there's nothing
  /// left to resume.
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
      _lastKnownOffset = 0;
      _progressStore.clear(_book.identityKey); // fire-and-forget
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
  /// `highlightRange` (and, for Module 6's purposes, as the new
  /// `_lastKnownOffset`).
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
    // MODULE 6: this is also exactly "how far the user has read" —
    // updated on every word so `progressFraction` stays live during
    // playback, but (unlike `_highlightRange`) never cleared by `stop()`,
    // so the progress indicator still reflects real progress afterward.
    _lastKnownOffset = globalStart;

    _notify();
  }

  /// Finds the index (into `_chunks`) of the chunk that contains a given
  /// global character offset — the chunk-level equivalent of
  /// `BookContent.paragraphIndexAt`, and built the same way (binary
  /// search over a list already sorted by ascending offset) for the same
  /// reason: this runs against a list that could hold thousands of
  /// chunks for a large book.
  ///
  /// WHY THIS ALONE ISN'T ENOUGH — AND ISN'T MEANT TO BE:
  /// this only picks the right CHUNK; it says nothing about WHERE inside
  /// that chunk the saved offset actually was. `resumeFromSaved` (the
  /// only caller) pairs this with `_pendingResumeLocalOffset` for
  /// exactly that reason — see that field's doc comment for the bug
  /// that existed before that pairing was added (every resume speaking
  /// its containing chunk from that chunk's own start, which is
  /// indistinguishable from "the start of the book" whenever that
  /// chunk IS most or all of the book).
  int _chunkIndexForOffset(int offset) {
    int low = 0;
    int high = _chunks.length - 1;

    while (low <= high) {
      final int mid = (low + high) ~/ 2;
      final PlaybackChunk chunk = _chunks[mid];

      if (offset < chunk.startOffset) {
        high = mid - 1;
      } else if (offset >= chunk.endOffset) {
        low = mid + 1;
      } else {
        return mid;
      }
    }

    return low.clamp(0, _chunks.length - 1);
  }

  /// Writes the current [_lastKnownOffset] to storage. Fire-and-forget
  /// wherever it's called from (`pause()`, `stop()`,
  /// `didChangeAppLifecycleState`) — none of those callers need to await
  /// a disk write to do their own job.
  void _saveProgress() {
    if (_lastKnownOffset <= 0) return; // nothing meaningful to save yet
    _progressStore.save(
      ReadingProgress(
        bookPath: _book.identityKey,
        characterOffset: _lastKnownOffset,
        // MODULE 8: `_totalCharacters` is already computed once in
        // `_loadContent` (see that field's own doc comment) — passing it
        // through here costs nothing extra to compute, and is what lets
        // the Library screen show a real percentage per book without
        // re-extracting every book's text itself.
        totalCharacters: _totalCharacters,
        lastReadAt: DateTime.now(),
      ),
    );
  }

  /// MODULE 6 — the "backgrounding" save trigger. `AppLifecycleState`
  /// transitions to `paused` when the app is no longer visible to the
  /// user at all (home button, app switcher, screen lock) — the point at
  /// which the process could be killed by the OS at any time without
  /// further warning, making it the right moment to persist progress
  /// defensively. `inactive` (a brief transitional state, e.g. a system
  /// dialog or notification shade transiently covering the app) is
  /// included too, since it's cheap to save slightly more often than
  /// strictly necessary, and this errs toward never losing progress over
  /// optimizing away a rare, inexpensive extra write.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    // Fire-and-forget: dispose() is synchronous and can't be awaited, but
    // we still want the native engine told to stop rather than left
    // reading a book whose screen just closed, and this session's last
    // known position saved rather than silently dropped.
    _ttsService.stop();
    _saveProgress();
    super.dispose();
  }
}
