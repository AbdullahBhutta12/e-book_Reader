import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/book_content.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../controllers/book_reader_controller.dart';

/// Renders a [BookContent]'s paragraphs as a scrollable reading view.
///
/// WHY `ListView.builder` INSTEAD OF A `Column` OF `Text` WIDGETS (this
/// is the specific decision behind the "good performance with large
/// books" requirement):
/// A `Column` builds and lays out EVERY child immediately, all at once,
/// whether it's on screen or not. For a short story that's invisible; for
/// a 120,000-word novel split into a few thousand paragraphs, building
/// several thousand `Text` widgets up front — most of which the user
/// can't even see yet — is real, measurable jank on first frame.
/// `ListView.builder` only builds the paragraphs currently visible (plus
/// a small buffer just off-screen), and recycles widgets as you scroll.
/// The book's full text still lives in memory as one `BookContent`
/// object (that part's cheap — even a huge novel is only a few
/// megabytes of text) — it's specifically the WIDGET TREE that stays
/// small, which is what actually matters for scroll performance.
class BookContentView extends StatefulWidget {
  const BookContentView({super.key, required this.content});

  final BookContent content;

  @override
  State<BookContentView> createState() => _BookContentViewState();
}

/// WHY THIS IS NOW A StatefulWidget (it used to be a plain
/// StatelessWidget rendering just a `ListView.builder`):
///
/// ROOT CAUSE OF "resume dialog appears, but the book still opens from
/// the beginning": `BookReaderController.resumeFromSaved` already
/// correctly restored `_currentChunkIndex` — a subsequent Play press
/// genuinely does start speaking (and highlighting) from the resumed
/// chunk, not from the start of the book. But nothing ever told the
/// on-screen `ListView` itself to scroll anywhere — it always rendered
/// at its default (top) scroll position regardless of where playback
/// was about to resume from. A `ScrollController` is the standard
/// Flutter mechanism for imperatively moving a scroll view, and it needs
/// somewhere to live for the widget's lifetime — that's a `State`
/// object, not something a stateless `build()` can hold.
class _BookContentViewState extends State<BookContentView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Turns `BookReaderController.pendingScrollFraction` (a `0.0`–`1.0`
  /// fraction through the book — see that field's own doc comment for
  /// why a fraction, not a pixel offset) into an actual scroll jump,
  /// exactly once per resume.
  ///
  /// WHY `addPostFrameCallback`, NOT DONE DIRECTLY IN `build()`: the
  /// `ListView` needs to have actually laid out at least once before
  /// `_scrollController.position.maxScrollExtent` is meaningful — before
  /// the first frame, the scroll view has no attached `ScrollPosition`
  /// yet at all. Scheduling this for right after the current frame
  /// finishes is the same safe, standard pattern already used elsewhere
  /// in this screen for post-build side effects (see
  /// `_ResumePromptListener`/`_TtsErrorListener` in `reader_screen.dart`).
  void _applyPendingScroll(double fraction) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final double maxExtent = _scrollController.position.maxScrollExtent;
      final double target = (fraction * maxExtent).clamp(0.0, maxExtent);
      _scrollController.jumpTo(target);
      // Reported back to the controller so this can never fire again for
      // the same resume — see `consumePendingScroll`'s doc comment.
      context.read<BookReaderController>().consumePendingScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final double? pendingScrollFraction =
        context.select<BookReaderController, double?>(
      (controller) => controller.pendingScrollFraction,
    );

    if (pendingScrollFraction != null) {
      _applyPendingScroll(pendingScrollFraction);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      itemCount: widget.content.paragraphs.length,
      itemBuilder: (context, index) {
        final paragraph = widget.content.paragraphs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _ParagraphText(paragraph: paragraph),
        );
      },
    );
  }
}

/// One paragraph's text, optionally rendering a highlighted word inside
/// it — this is Module 5's entire visual footprint.
///
/// WHY THIS SUBSCRIBES TO `highlightRange` HERE, PER-PARAGRAPH, RATHER
/// THAN `BookContentView` WATCHING IT ONCE AT THE TOP:
/// `BookReaderController.highlightRange` changes roughly once per
/// spoken word — many times a second during active playback. If
/// `BookContentView` watched it directly, EVERY visible paragraph would
/// rebuild on EVERY word, even the ones nowhere near what's currently
/// being read — exactly the "unnecessary rebuilds" this module is
/// required to avoid, and for a long novel with many paragraphs on
/// screen at once, a real, avoidable performance cost.
///
/// `context.select` here instead gives each `_ParagraphText` its OWN,
/// narrow subscription: "the highlighted range, but only if it actually
/// falls inside THIS paragraph — otherwise `null`." A word being spoken
/// three paragraphs away produces a `null` result for this paragraph
/// both before and after the change, so `select` correctly sees no
/// change and skips the rebuild entirely. Only the (at most two)
/// paragraphs actually gaining or losing the highlight ever rebuild —
/// this is also exactly why `highlightRange` is a single record: it
/// gives `select` one structurally-comparable value to key off, instead
/// of two fields that could drift out of sync with each other.
class _ParagraphText extends StatelessWidget {
  const _ParagraphText({required this.paragraph});

  final BookParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    final ({int start, int end})? localRange =
        context.select<BookReaderController, ({int start, int end})?>(
      (controller) {
        final range = controller.highlightRange;
        if (range == null) return null;
        // Clip the book-wide highlight range down to local offsets
        // within THIS paragraph's own text — and return `null` (not a
        // zero-length or out-of-bounds range) whenever it doesn't
        // overlap this paragraph at all. Returning `null` in that case,
        // rather than some sentinel range, is what lets `select` treat
        // "highlight is elsewhere" as a stable, unchanging value across
        // however many other paragraphs the highlight passes through.
        final int overlapStart = range.start < paragraph.startOffset
            ? paragraph.startOffset
            : (range.start > paragraph.endOffset
                ? paragraph.endOffset
                : range.start);
        final int overlapEnd = range.end > paragraph.endOffset
            ? paragraph.endOffset
            : (range.end < paragraph.startOffset
                ? paragraph.startOffset
                : range.end);
        if (overlapEnd <= overlapStart) return null;
        return (
          start: overlapStart - paragraph.startOffset,
          end: overlapEnd - paragraph.startOffset,
        );
      },
    );

    if (localRange == null) {
      // The common case for the vast majority of paragraphs at any
      // given moment: no highlight to render, so a plain `Text` is all
      // that's needed — no `RichText`/`TextSpan` machinery for text that
      // isn't being spoken right now.
      return Text(paragraph.text, style: AppTextStyles.readingBody);
    }

    final TextStyle baseStyle = AppTextStyles.readingBody;
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: paragraph.text.substring(0, localRange.start)),
          TextSpan(
            text: paragraph.text.substring(localRange.start, localRange.end),
            style: baseStyle.copyWith(
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: paragraph.text.substring(localRange.end)),
        ],
      ),
    );
  }
}
