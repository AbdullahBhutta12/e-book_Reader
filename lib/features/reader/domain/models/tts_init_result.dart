/// Every possible outcome of starting up the text-to-speech engine.
///
/// Same reasoning as [BookImportResult] and [BookContentResult]: modeling
/// each real outcome as its own type (instead of a bare `bool success`)
/// lets `BookReaderController` show a specific, honest, professional
/// message for each distinct failure — "no TTS engine installed" is a
/// genuinely different problem from "the English voice isn't installed,"
/// and the user can act on the second one (install the voice) in a way
/// they can't for the first.
sealed class TtsInitResult {
  const TtsInitResult();
}

/// The engine is available, the requested language is installed, and
/// playback is ready to use.
final class TtsInitSuccess extends TtsInitResult {
  const TtsInitSuccess();
}

/// No TTS engine could be found on this device at all (`getLanguages`
/// returned nothing to work with). This is rare — most Android devices
/// ship with one — but not impossible on stripped-down or custom ROMs.
final class TtsInitUnavailable extends TtsInitResult {
  const TtsInitUnavailable();
}

/// A TTS engine exists, but the specific language/voice this app
/// requested isn't installed on it.
final class TtsInitUnsupportedLanguage extends TtsInitResult {
  const TtsInitUnsupportedLanguage(this.languageCode);
  final String languageCode;
}

/// Something else went wrong during setup — an unexpected platform
/// exception this app didn't specifically anticipate.
///
/// [debugMessage] is intentionally never shown to the user directly (see
/// `BookReaderController` — same reasoning as its content-loading error
/// handling): a raw platform exception string is a developer detail, not
/// something a reader can act on.
final class TtsInitFailure extends TtsInitResult {
  const TtsInitFailure(this.debugMessage);
  final String debugMessage;
}
