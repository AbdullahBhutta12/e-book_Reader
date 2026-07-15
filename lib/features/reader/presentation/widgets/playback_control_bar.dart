import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/tts_playback_state.dart';

/// The Play / Pause / Stop control bar shown at the bottom of the Reader
/// screen while a book's text is loaded.
///
/// WHY THIS WIDGET HOLDS NO LOGIC OF ITS OWN:
/// Same pattern as `ImportBookButton` back in Module 2 — this is a "dumb"
/// widget. It doesn't know what `TtsPlaybackState` values mean for
/// `BookReaderController`, doesn't call `TtsService` or `flutter_tts`,
/// and doesn't decide what happens when a button is tapped. It only
/// renders whatever [playbackState] it's handed and forwards taps to the
/// callbacks its parent supplies. `ReaderScreen` is the only place that
/// wires these callbacks to real controller methods — keeping the
/// widget itself reusable and trivially testable in isolation.
class PlaybackControlBar extends StatelessWidget {
  const PlaybackControlBar({
    super.key,
    required this.playbackState,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
  });

  final TtsPlaybackState playbackState;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = playbackState == TtsPlaybackState.playing;
    final bool isStopped = playbackState == TtsPlaybackState.stopped;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Stop: disabled when nothing is playing or paused — you
              // can't stop something that isn't running.
              _ControlButton(
                icon: Icons.stop,
                label: AppStrings.ttsStopLabel,
                onPressed: isStopped ? null : onStop,
              ),
              // Play: disabled while already playing — prevents
              // double-tapping from starting a second overlapping speak()
              // request. Stays ENABLED while paused, since tapping Play
              // during a pause is exactly how playback resumes.
              _ControlButton(
                icon: Icons.play_arrow,
                label: AppStrings.ttsPlayLabel,
                onPressed: isPlaying ? null : onPlay,
                isPrimary: true,
              ),
              // Pause: only enabled while actively playing — disabled
              // both when stopped (nothing to pause) AND when already
              // paused (can't pause twice).
              _ControlButton(
                icon: Icons.pause,
                label: AppStrings.ttsPauseLabel,
                onPressed: isPlaying ? onPause : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single icon + label button, shared by all three controls so their
/// disabled/enabled styling can never drift out of sync between them.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;

  /// `null` is Flutter's own built-in way to disable a button — no
  /// separate boolean needed, same idiom used by `ImportBookButton`.
  final VoidCallback? onPressed;

  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final Color color = !isEnabled
        ? AppColors.textSecondary.withValues(alpha: 0.4)
        : (isPrimary ? AppColors.primary : AppColors.textPrimary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: isPrimary ? 36 : 28),
          color: color,
          tooltip: label,
        ),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
