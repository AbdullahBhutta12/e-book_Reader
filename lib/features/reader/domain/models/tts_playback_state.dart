/// The three states text-to-speech playback can be in.
///
/// WHY A PLAIN ENUM (not an enhanced enum like [SupportedBookFormat]):
/// These three values carry no data of their own — there's nothing to
/// attach a constructor/field to. Reaching for enhanced-enum syntax here
/// anyway would be complexity with no payoff; a plain enum is the
/// correct, simplest tool for a closed set of bare states.
///
/// WHY ONLY THREE STATES (not, say, separate "idle" and "stopped"
/// states, or a distinct "loading"/"buffering" state):
/// Every real flutter_tts callback this app listens to collapses onto
/// one of exactly these three from the UI's point of view:
///   - `onStart` / `onContinue`  → [playing]
///   - `onPause`                → [paused]
///   - `onCompletion` / `onCancel` / an error → [stopped]
/// "Never started yet" and "finished/cancelled/errored" are all
/// indistinguishable from the Play/Pause/Stop button bar's perspective —
/// in every one of those cases, Play should be enabled and Pause/Stop
/// should not. Modeling them as separate states would just mean more
/// cases to keep in sync for zero behavioral difference.
enum TtsPlaybackState { stopped, playing, paused }
