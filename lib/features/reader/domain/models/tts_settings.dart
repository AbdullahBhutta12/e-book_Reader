/// The user's saved playback preference — speech rate and pitch —
/// persisted across app sessions and applied to every book, not just
/// the one open when it was last changed.
///
/// WHY THIS ISN'T PER-BOOK (unlike [ReadingProgress]): how fast someone
/// wants a book read aloud is a preference about THEM, not about any
/// particular book — there's no reason picking a comfortable rate while
/// reading one book shouldn't carry over to the next one they open.
class TtsSettings {
  const TtsSettings({required this.speechRate, required this.pitch});

  /// flutter_tts's own `0.0`–`1.0` speech-rate scale — stored and applied
  /// verbatim, never converted to/from any other unit.
  final double speechRate;

  /// flutter_tts's own pitch scale, where `1.0` is the engine's normal
  /// pitch.
  final double pitch;
}
