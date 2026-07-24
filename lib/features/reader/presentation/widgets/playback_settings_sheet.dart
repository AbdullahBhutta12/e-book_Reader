import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../controllers/book_reader_controller.dart';

/// Lets the user adjust speech rate and pitch, live, while a book is
/// open — persisted (via `BookReaderController.setSpeechRate`/`setPitch`)
/// so the choice carries over to every book, not just this one.
///
/// Same shape as `BookInfoSheet`: call [show] rather than constructing
/// this directly, for the same reason — it keeps the
/// `showModalBottomSheet` boilerplate in one place.
class PlaybackSettingsSheet extends StatelessWidget {
  const PlaybackSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // The sheet reads `BookReaderController` via `Provider` — passing
      // the ORIGINAL context (not the bottom sheet's own builder
      // context, which sits outside the page route and therefore
      // outside the `ChangeNotifierProvider` that only wraps the Reader
      // screen's own subtree) is what makes `context.watch` below able
      // to find it at all.
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<BookReaderController>(),
        child: const PlaybackSettingsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A whole small, short-lived sheet watching the controller directly
    // (rather than `context.select`-ing each field separately, as the
    // main Reader screen carefully does) is a deliberate, different
    // choice here: this sheet IS the slider — there's no unrelated
    // content elsewhere in it that unnecessary rebuilds could waste work
    // on, so the extra precision `select` buys elsewhere isn't worth the
    // additional code here.
    final controller = context.watch<BookReaderController>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              AppStrings.playbackSettingsTitle,
              style: AppTextStyles.heading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 20),
            _SettingSlider(
              icon: Icons.speed_outlined,
              label: AppStrings.speechRateLabel,
              value: controller.speechRate,
              // flutter_tts's own usable range for `setSpeechRate` — the
              // bottom end is already noticeably slow, and this app's
              // engine-level default (`TtsService.defaultSpeechRate`) is
              // comfortably inside it, not at either extreme.
              min: 0.1,
              max: 1.0,
              onChanged: controller.setSpeechRate,
            ),
            const SizedBox(height: 20),
            _SettingSlider(
              icon: Icons.graphic_eq,
              label: AppStrings.pitchLabel,
              value: controller.pitch,
              // flutter_tts's own documented pitch range, centered on its
              // normal value of 1.0 (`TtsService.defaultPitch`).
              min: 0.5,
              max: 2.0,
              onChanged: controller.setPitch,
            ),
          ],
        ),
      ),
    );
  }
}

/// One labeled slider row — extracted so the rate and pitch controls
/// above are one call each instead of two near-identical `Column`s of
/// `Icon` + `Text` + `Slider` written out by hand.
class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.subheading),
            const Spacer(),
            Text(
              value.toStringAsFixed(2),
              style: AppTextStyles.subheading.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
