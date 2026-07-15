import 'dart:developer' as developer;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_tts/flutter_tts.dart';
import '../domain/models/tts_init_result.dart';

/// Talks to the device's native text-to-speech engine and exposes it in
/// domain-friendly terms.
///
/// WHY THIS CLASS LIVES IN `data/`, NOT `domain/`:
/// Exactly the same reasoning as `BookImportService`: this is the ONLY
/// file in the whole `reader` feature that imports `package:flutter_tts`
/// — a third-party plugin that talks to the operating system's TTS
/// engine. If this app ever needed a different TTS backend, only this
/// file would change.
///
/// WHY THIS ISN'T HIDDEN BEHIND AN ABSTRACT INTERFACE (unlike
/// `TextExtractor`, which has one):
/// `TextExtractor` needed an abstraction because multiple concrete
/// extractors already exist in this app's design (`PlainTextExtractor`
/// now; PDF/EPUB extractors later), chosen dynamically via
/// `TextExtractorFactory`. There is exactly one text-to-speech backend
/// this app will ever reasonably swap to, so an interface here would be
/// abstraction with no real second implementation behind it —
/// unnecessary complexity for its own sake. `TtsService` is still fully
/// injectable into `BookReaderController` (constructor injection with a
/// default), which is what actually matters for testability.
class TtsService {
  TtsService({FlutterTts? flutterTts}) : _tts = flutterTts ?? FlutterTts();

  final FlutterTts _tts;

  /// Hardcoded for V1 — matches this app's TXT-only, English-first scope.
  /// Voice/language selection is a natural fit for Module 7's UI polish
  /// pass, not this module.
  static const String _language = 'en-US';

  /// Registers every native callback `BookReaderController` needs to
  /// react to, translating flutter_tts's raw callback API into plain
  /// Dart function parameters. Called exactly ONCE, right after this
  /// service is constructed.
  ///
  /// WHY THIS IS A SEPARATE METHOD INSTEAD OF WIRING THESE UP INSIDE
  /// `TtsService`'s OWN CONSTRUCTOR:
  /// The callbacks need to call back into `BookReaderController`'s own
  /// methods (e.g. "when speech starts, set MY playback state to
  /// playing"). `BookReaderController` can't pass `this.someMethod` to
  /// `TtsService`'s constructor from within its OWN constructor's
  /// initializer list — at that point in a Dart constructor, `this` isn't
  /// fully initialized yet. Calling `attachHandlers` from the
  /// constructor's BODY (not its initializer list) sidesteps that: by
  /// then, `_ttsService` is already assigned and `this` is safe to
  /// reference.
  void attachHandlers({
    required void Function() onStart,
    required void Function() onContinue,
    required void Function() onPause,
    required void Function() onCompletion,
    required void Function() onCancel,
    required void Function(String message) onError,
    void Function(String word, int startOffset, int endOffset)? onProgress,
  }) {
    _tts.setStartHandler(onStart);
    _tts.setContinueHandler(onContinue);
    _tts.setPauseHandler(onPause);
    _tts.setCompletionHandler(onCompletion);
    _tts.setCancelHandler(onCancel);
    _tts.setErrorHandler((dynamic message) => onError(message.toString()));

    // MODULE 5 — word-boundary highlighting.
    //
    // WHY OPTIONAL (nullable, only wired if the caller supplies it):
    // Every OTHER handler above is `required` because the controller has
    // depended on them since Module 4 — playback literally can't work
    // without them. Progress reporting is different: it's read-only
    // information ON TOP of a playback pipeline that already works
    // completely without it. Making it optional keeps that fact honest
    // in the type signature.
    //
    // WHY THIS CANNOT BE THE SOURCE OF ANY PAUSE/RESUME TIMING CHANGE:
    // flutter_tts exposes Android's native `onRangeStart` callback (and
    // iOS's equivalent word-boundary event) through this single
    // cross-platform method. It already fires during ordinary playback
    // today — `pause()` has relied on it since Module 4 to remember a
    // mid-chunk resume offset. This only adds a SECOND listener for the
    // same, already-flowing event; it doesn't change when or how often
    // the native engine emits it.
    //
    // WHY THE PARAMETERS ARE PASSED THROUGH VERBATIM (no offset math
    // here): `startOffset`/`endOffset` are local to whichever chunk is
    // currently speaking — this class has no idea which `PlaybackChunk`
    // that is, and shouldn't; `TtsService` stays focused only on native
    // TTS. Translating a local offset into a book-wide one is
    // `BookReaderController`'s job, since it's the one that knows which
    // chunk is playing.
    if (onProgress != null) {
      _tts.setProgressHandler((
        String text,
        int startOffset,
        int endOffset,
        String word,
      ) {
        onProgress(word, startOffset, endOffset);
      });
    }
  }

  /// Checks the engine is usable and configures it, WITHOUT speaking
  /// anything yet. Must complete before [speak] is ever called.
  Future<TtsInitResult> initialize() async {
    try {
      final dynamic rawLanguages = await _tts.getLanguages;
      final List<dynamic> languages =
          rawLanguages is List ? rawLanguages : const [];

      // No engine, or an engine with zero installed languages — either
      // way, there's genuinely nothing this app can do to speak text on
      // this device.
      if (languages.isEmpty) {
        return const TtsInitUnavailable();
      }

      final bool? isAvailable = await _tts.isLanguageAvailable(_language);
      if (isAvailable != true) {
        return const TtsInitUnsupportedLanguage(_language);
      }

      await _tts.setLanguage(_language);
      // Explicitly force QUEUE_FLUSH (0) rather than relying on
      // flutter_tts's own unstated default. Every `speak()` call this
      // service ever makes — the very first chunk, an auto-advance to
      // the next chunk, a Pause->Play resume, or a Stop->Play restart —
      // goes through the exact same `speak()` method
      // (`TtsService.speak`, called from
      // `BookReaderController._speakCurrentChunk`). QUEUE_FLUSH tells
      // the native Android engine to unconditionally discard anything
      // still pending in its own internal playback/synthesis queue
      // before honoring each new request, so a long sequential session
      // (hundreds of chunks, for a large book) can never leave the
      // engine with backlog to work through before a Play/Resume tap
      // actually starts making sound. This does NOT affect the
      // Android-side pause/resume offset tracking described on
      // `pause()` below — that mechanism is keyed off `onRangeStart`
      // progress, not queue mode.
      await _tts.setQueueMode(0);
      // A moderate default rate — flutter_tts's raw platform default is
      // often uncomfortably fast for continuous narration. Voice/rate
      // customization is a Module 7 concern; this is just a sane default.
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);

      return const TtsInitSuccess();
    } on PlatformException catch (e) {
      return TtsInitFailure(e.message ?? e.code);
    } catch (e) {
      return TtsInitFailure(e.toString());
    }
  }

  /// Starts speaking [text] — or, if playback was previously paused,
  /// resumes it. Returns `true` if the platform accepted the request.
  ///
  /// WHY THERE'S NO SEPARATE `resume()` METHOD:
  /// flutter_tts's Android implementation doesn't have a native "resume"
  /// concept — see the doc comment on `pause()` below. Resuming is done
  /// by calling `speak()` again with the SAME text as before; the plugin
  /// remembers where playback was paused and picks up from there. As of
  /// Module 4.2's chunked playback, "the same text" is one
  /// `PlaybackChunk.text` (not `BookContent.fullText` — this comment
  /// previously said so, from before chunking existed). `_speakCurrentChunk`
  /// in `BookReaderController` always re-passes the identical chunk
  /// string for a paused chunk, so that assumption still holds.
  Future<bool> speak(String text) =>
      _runAndCheckSuccess(() => _tts.speak(text));

  /// Pauses playback.
  ///
  /// ANDROID LIMITATION: Android's native TextToSpeech API has no
  /// built-in pause concept at all — flutter_tts implements it as a
  /// workaround, using the word-boundary callback (`onRangeStart`) to
  /// remember the character offset playback had reached, then slicing
  /// the remembered text from that offset the next time `speak()` is
  /// called. Because this workaround depends on `onRangeStart`, it only
  /// works on **Android API 26 (Android 8.0) and above**. iOS, Web, and
  /// Windows support pause natively through their own platform APIs with
  /// no such restriction.
  Future<bool> pause() => _runAndCheckSuccess(() => _tts.pause());

  /// Stops playback entirely and resets position — a subsequent [speak]
  /// call starts over from the beginning, not from a paused offset.
  Future<bool> stop() => _runAndCheckSuccess(() => _tts.stop());

  /// Runs a single flutter_tts call, treating a `1` result as success and
  /// EVERY other outcome — a different return value, or any thrown
  /// exception — as a plain `false`.
  ///
  /// WHY THIS EXISTS: `speak()`, `pause()`, and `stop()` used to each
  /// write out the identical "try the call, catch anything, compare the
  /// result to 1" shape by hand. Three copies of the same four lines is
  /// exactly the kind of duplication worth naming once and reusing —
  /// especially since it's also where "every async TTS call is
  /// exception-safe" is enforced; that guarantee now lives in ONE place
  /// instead of needing to be remembered separately in three methods.
  ///
  /// TEMPORARY DIAGNOSTIC PATCH — DO NOT LEAVE THIS IN PRODUCTION:
  /// This method previously caught every exception with `catch (_)`,
  /// which silently discarded whatever the real platform exception was —
  /// exactly what made the large-`.txt`-file "Error from TextToSpeech
  /// (speak)" bug impossible to diagnose from the SnackBar message alone.
  /// The `catch (error, stackTrace)` clause below now captures both and
  /// writes them to `dart:developer`'s log before still returning
  /// `false` — the return behavior and the public API are UNCHANGED;
  /// this only adds visibility into what was already happening. Once the
  /// real cause is identified, this logging call should be removed (or
  /// gated behind a debug-only flag) — it is not meant to ship.
  Future<bool> _runAndCheckSuccess(Future<dynamic> Function() action) async {
    try {
      final dynamic result = await action();
      return result == 1;
    } catch (error, stackTrace) {
      developer.log(
        'TtsService call failed: $error',
        name: 'TtsService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
