import 'package:flutter/foundation.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/text_extractor_factory.dart';
import '../../domain/models/book_content_result.dart';
import '../../domain/models/book_file.dart';
import '../../domain/models/supported_book_format.dart';

/// Owns the Reader screen's state: right now, just "is the book loaded,
/// and if so, what happened?" — Module 4 will extend this same class with
/// TTS playback state, and Module 5 with the currently-highlighted
/// sentence/word, rather than introducing a second, separate controller.
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
/// WHY THIS IS SCOPED TO THE READER SCREEN (created when it opens,
/// destroyed when it closes) INSTEAD OF LIVING AT THE TRUE APP ROOT:
/// "Which book is open and how far did the TTS engine get reading it" is
/// only meaningful while a book is actually open. Putting it in a
/// provider that lives for the entire app's lifetime — even before any
/// book has ever been opened, or after the user has navigated back to
/// the Home screen — would mean carrying around stale or meaningless
/// state, and worse, a `ChangeNotifier` that's never disposed until the
/// whole app closes. `provider`'s job here is to share this state across
/// the WIDGETS WITHIN the Reader screen (the content view now; the
/// playback bar and highlighted text in Module 4/5) — not to make it
/// global.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required BookFile book,
    TextExtractorFactory? extractorFactory,
  })  : _book = book,
        _extractorFactory = extractorFactory ?? const TextExtractorFactory() {
    _loadContent();
  }

  final BookFile _book;

  /// Injected via the constructor with a sensible default — same
  /// dependency-injection pattern used for `BookImportService` in
  /// `HomeScreen` back in Module 2, for the same reason: a test can
  /// supply a fake factory without touching the real file system.
  final TextExtractorFactory _extractorFactory;

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

  Future<void> _loadContent() async {
    // SupportedBookFormat.fromExtension can only return null here if
    // BookImportService's own validation (Module 2) somehow let an
    // unrecognized extension through — which shouldn't happen, but we
    // still handle it explicitly rather than assuming it can't.
    final format = SupportedBookFormat.fromExtension(_book.extension);
    if (format == null) {
      _finishWith(BookContentUnsupportedFormat(_book.extension));
      return;
    }

    final extractor = _extractorFactory.extractorFor(format);
    if (extractor == null) {
      _finishWith(BookContentUnsupportedFormat(_book.extension));
      return;
    }

    try {
      final content = await extractor.extract(_book);
      _finishWith(BookContentLoaded(content));
    } catch (_) {
      // We deliberately don't surface the raw exception message to the
      // user — it's typically a low-level I/O error that means nothing
      // to someone who isn't a developer. A clear, honest, generic
      // message serves them better than a stack trace fragment.
      _finishWith(
        const BookContentLoadFailure(AppStrings.readerLoadFailureMessage),
      );
    }
  }

  void _finishWith(BookContentResult result) {
    _result = result;
    notifyListeners();
  }
}
