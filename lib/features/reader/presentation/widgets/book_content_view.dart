import 'package:flutter/material.dart';
import '../../domain/models/book_content.dart';
import '../../../../core/theme/app_text_styles.dart';

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
class BookContentView extends StatelessWidget {
  const BookContentView({super.key, required this.content});

  final BookContent content;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      itemCount: content.paragraphs.length,
      itemBuilder: (context, index) {
        final paragraph = content.paragraphs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            paragraph.text,
            style: AppTextStyles.readingBody,
          ),
        );
      },
    );
  }
}
