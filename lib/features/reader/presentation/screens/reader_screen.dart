import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../domain/models/book_content_result.dart';
import '../../domain/models/book_file.dart';
import '../../domain/models/supported_book_format.dart';
import '../controllers/book_reader_controller.dart';
import '../widgets/book_content_view.dart';
import '../widgets/book_info_sheet.dart';
import '../widgets/playback_control_bar.dart';
import '../widgets/playback_settings_sheet.dart';

/// Shown after a book has been successfully imported and validated.
///
/// Module 2's version of this screen only displayed file metadata.
/// Module 3 added the real thing: extracting and displaying the book's
/// text. Module 4 adds a working Play / Pause / Stop control bar wired to
/// `BookReaderController`'s new TTS state.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.book});

  final BookFile book;

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider is created HERE, scoped to this screen —
    // not at the app's root. It's built once when ReaderScreen is pushed
    // and automatically disposed (its `dispose()` called, listeners
    // cleaned up, and — as of Module 4 — the TTS engine told to stop)
    // when the screen is popped.
    return ChangeNotifierProvider(
      create: (_) => BookReaderController(book: book),
      child: const _ReaderView(),
    );
  }
}

/// MODULE 4 REBUILD-SCOPING NOTE:
///
/// This widget used to do a single blanket `context.watch<
/// BookReaderController>()` and rebuild its entire Scaffold — AppBar,
/// book content, everything — in response to ANY change on the
/// controller. That was fine when the controller only ever changed once
/// (when content finished loading). Now that play/pause/stop can change
/// the controller's state repeatedly during a single reading session,
/// that blanket watch would rebuild the AppBar and re-run the (potentially
/// large) book content view every single time the user taps a playback
/// button — work that produces an IDENTICAL AppBar and identical content
/// each time, since neither depends on playback state at all.
///
/// Instead, `_ReaderView` and each of its children below use
/// `context.select` to subscribe to only the specific field(s) they
/// actually render from. Each piece of this screen now only rebuilds when
/// the slice of state IT depends on actually changes:
///   - `_ReaderView` itself           → only `book` (set once, never
///                                      changes again for this instance)
///   - `_ReaderContentSection`        → only `result`
///   - `_ReaderPlaybackSection`       → only "is content loaded" (bool)
///   - `_PlaybackArea` (inside it)    → the TTS fields — the ONLY part of
///                                      this screen that's SUPPOSED to
///                                      rebuild on every play/pause/stop
///   - `_TtsErrorListener`            → only `ttsErrorMessage`
class _ReaderView extends StatelessWidget {
  const _ReaderView();

  @override
  Widget build(BuildContext context) {
    final BookFile book = context.select<BookReaderController, BookFile>(
      (controller) => controller.book,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: AppStrings.playbackSettingsButtonTooltip,
            icon: const Icon(Icons.tune),
            onPressed: () => PlaybackSettingsSheet.show(context),
          ),
          IconButton(
            tooltip: AppStrings.bookInfoButtonTooltip,
            icon: const Icon(Icons.info_outline),
            onPressed: () => BookInfoSheet.show(context, book),
          ),
        ],
        bottom: const _ProgressIndicatorBar(),
      ),
      body: const Stack(
        children: [
          SafeArea(child: _ReaderContentSection()),
          // Neither of these renders anything visible — see their own
          // doc comments. Placed in a Stack alongside the real content
          // purely so they participate in the widget tree and can react
          // to their respective piece of controller state.
          _TtsErrorListener(),
          _ResumePromptListener(),
        ],
      ),
      bottomNavigationBar: const _ReaderPlaybackSection(),
    );
  }
}

/// A slim progress bar in the AppBar showing how far through the book the
/// user has read (`BookReaderController.progressFraction`).
///
/// WHY `context.select` HERE TOO (not a blanket watch on `_ReaderView`):
/// `progressFraction` updates on every spoken word during playback — the
/// same rebuild-storm risk `_PlaybackArea` and `_ParagraphText` already
/// guard against elsewhere in this screen. Isolating it to its own tiny
/// widget means only this 3-pixel-tall bar repaints on every word, not
/// the AppBar's title or actions around it.
class _ProgressIndicatorBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _ProgressIndicatorBar();

  @override
  Size get preferredSize => const Size.fromHeight(3);

  @override
  Widget build(BuildContext context) {
    final double fraction = context.select<BookReaderController, double>(
      (controller) => controller.progressFraction,
    );
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 3,
      backgroundColor: AppColors.border,
      color: AppColors.primary,
    );
  }
}

/// Shows a Resume-or-Start-Over dialog when
/// `BookReaderController.pendingResumeOffset` is non-null, then resolves
/// it via the controller's `resumeFromSaved`/`dismissResumePrompt` based
/// on the user's choice — renders nothing visible itself.
///
/// Same "why this can't be inline in build()" reasoning as
/// `_TtsErrorListener` above: showing a dialog is a side effect, and
/// `context.select` means this widget (and therefore this
/// `addPostFrameCallback`) only re-runs when `pendingResumeOffset`
/// itself changes value — it can't fire a second time for the same
/// still-unresolved prompt just because something else on screen
/// rebuilt.
class _ResumePromptListener extends StatelessWidget {
  const _ResumePromptListener();

  @override
  Widget build(BuildContext context) {
    final int? pendingResumeOffset =
        context.select<BookReaderController, int?>(
      (controller) => controller.pendingResumeOffset,
    );

    if (pendingResumeOffset != null) {
      final controller = context.read<BookReaderController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          // Forces an explicit choice — dismissing by tapping outside
          // the dialog would leave `pendingResumeOffset` non-null with
          // no way for the user to make it go away, which is worse than
          // requiring one deliberate tap.
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text(AppStrings.resumeDialogTitle),
            content: const Text(AppStrings.resumeDialogMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  controller.dismissResumePrompt();
                },
                child: const Text(AppStrings.startOverButtonLabel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  controller.resumeFromSaved();
                },
                child: const Text(AppStrings.resumeButtonLabel),
              ),
            ],
          ),
        );
      });
    }

    return const SizedBox.shrink();
  }
}

/// Renders the book's content — isolated from playback-state churn by
/// selecting only `result`, which is set once when loading finishes and
/// never changes again for the rest of this screen's lifetime.
class _ReaderContentSection extends StatelessWidget {
  const _ReaderContentSection();

  @override
  Widget build(BuildContext context) {
    final BookContentResult? result =
        context.select<BookReaderController, BookContentResult?>(
      (controller) => controller.result,
    );
    return _ReaderBody(result: result);
  }
}

/// Decides WHETHER to show the playback bar at all (there's nothing to
/// read aloud if the book failed to load, or isn't readable yet), without
/// subscribing to the TTS fields themselves — this widget only rebuilds
/// when content finishes loading, not on every play/pause/stop.
class _ReaderPlaybackSection extends StatelessWidget {
  const _ReaderPlaybackSection();

  @override
  Widget build(BuildContext context) {
    final bool hasReadableContent = context.select<BookReaderController, bool>(
      (controller) => controller.result is BookContentLoaded,
    );

    if (!hasReadableContent) {
      return const SizedBox.shrink();
    }
    return const _PlaybackArea();
  }
}

/// The one part of this screen that's MEANT to rebuild on every
/// play/pause/stop tap and every TTS init/state change — everything
/// above this point in the tree is deliberately insulated from it.
class _PlaybackArea extends StatelessWidget {
  const _PlaybackArea();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BookReaderController>();

    if (controller.isTtsInitializing) {
      return const _TtsInitializingBar();
    }
    if (!controller.isTtsReady) {
      return _TtsUnavailableBar(reason: controller.ttsUnavailableReason!);
    }
    return PlaybackControlBar(
      playbackState: controller.playbackState,
      onPlay: controller.play,
      onPause: controller.pause,
      onStop: controller.stop,
    );
  }
}

/// Shows [BookReaderController.ttsErrorMessage] as a one-off SnackBar,
/// then clears it — renders nothing visible itself.
///
/// WHY THIS CAN'T JUST BE DONE INLINE INSIDE A NORMAL `build()` METHOD:
/// Showing a SnackBar and calling `clearTtsError()` (which itself calls
/// `notifyListeners()`) are SIDE EFFECTS — actions with consequences
/// beyond returning a widget. Flutter's `build()` methods must be pure:
/// triggering state changes or imperative UI actions (like
/// `ScaffoldMessenger.showSnackBar`) DURING a build is unsafe and can
/// throw ("setState()/markNeedsBuild() called during build"). Scheduling
/// the side effect with `addPostFrameCallback` defers it to run right
/// AFTER the current frame finishes building, which is the standard,
/// safe way to react to state during a build without violating that
/// rule.
class _TtsErrorListener extends StatelessWidget {
  const _TtsErrorListener();

  @override
  Widget build(BuildContext context) {
    final String? errorMessage =
        context.select<BookReaderController, String?>(
      (controller) => controller.ttsErrorMessage,
    );

    if (errorMessage != null) {
      final controller = context.read<BookReaderController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppSnackbar.showError(context, errorMessage);
        controller.clearTtsError();
      });
    }

    return const SizedBox.shrink();
  }
}

class _TtsInitializingBar extends StatelessWidget {
  const _TtsInitializingBar();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TtsUnavailableBar extends StatelessWidget {
  const _TtsUnavailableBar({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reason,
                  style: AppTextStyles.subheading.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks which state to render based on the controller's current result.
///
/// Same Dart 3 exhaustive-switch pattern used for `BookImportResult` in
/// Module 2 — `result` can be `null` (still loading) or one of
/// `BookContentResult`'s three subtypes, and every case is handled
/// explicitly.
class _ReaderBody extends StatelessWidget {
  const _ReaderBody({required this.result});

  final BookContentResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;

    if (result == null) {
      return const _LoadingState();
    }

    return switch (result) {
      BookContentLoaded(:final content) => content.paragraphs.isEmpty
          ? const _EmptyBookState()
          : BookContentView(content: content),
      BookContentNotYetReadable(:final format) =>
        _NotYetReadableState(format: format),
      BookContentLoadFailure(:final message) =>
        _LoadFailureState(message: message),
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            AppStrings.readerLoadingMessage,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyBookState extends StatelessWidget {
  const _EmptyBookState();

  @override
  Widget build(BuildContext context) {
    return const _StatusMessage(
      icon: Icons.insert_drive_file_outlined,
      title: AppStrings.readerEmptyBookTitle,
      message: AppStrings.readerEmptyBookMessage,
    );
  }
}

class _NotYetReadableState extends StatelessWidget {
  const _NotYetReadableState({required this.format});

  final SupportedBookFormat format;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: Icons.hourglass_empty_outlined,
      title: AppStrings.readerNotYetReadableTitle,
      message: AppStrings.readerNotYetReadableBody(format.extension),
    );
  }
}

class _LoadFailureState extends StatelessWidget {
  const _LoadFailureState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: Icons.error_outline,
      title: AppStrings.readerLoadFailureTitle,
      message: message,
    );
  }
}

/// Shared layout for every "nothing to show, here's why" state above.
///
/// Extracted for the same reason `BookDetailTile` was in Module 2: three
/// near-identical "icon + title + message, centered" layouts is exactly
/// the kind of UI duplication the "no duplicate code" rule is about.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.heading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.subheading,
            ),
          ],
        ),
      ),
    );
  }
}
