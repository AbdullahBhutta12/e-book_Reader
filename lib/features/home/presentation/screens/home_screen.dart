import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../reader/data/book_import_service.dart';
import '../../../reader/domain/models/book_import_result.dart';
import '../../../reader/presentation/screens/reader_screen.dart';
import '../widgets/import_book_button.dart';

/// The first screen the user sees when opening the app.
///
/// WHY THIS IS NOW A StatefulWidget (it was StatelessWidget in Module 1):
/// Module 1's doc comment on this class predicted this exact moment:
/// "Once we wire up real file picking in Module 2 (which will need to
/// show a loading spinner while a file is being read), that's exactly the
/// kind of change that will push this screen towards holding state."
/// That's now true — this screen owns one piece of mutable state
/// (`_isImporting`) that must trigger a rebuild (to show/hide the
/// spinner), and `StatelessWidget` has no mechanism for that. `setState`
/// is the simplest tool that does.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, BookImportService? importService})
      : _importService = importService ?? const BookImportService();

  /// The service used to pick a book file, injected through the
  /// constructor with a sensible default.
  ///
  /// WHY THIS PATTERN (instead of just writing
  /// `const BookImportService()` directly inside the State class):
  /// Accepting it as an optional constructor parameter costs nothing for
  /// normal use — `const HomeScreen()` still works with zero
  /// configuration. But it means a future widget test can do
  /// `HomeScreen(importService: FakeBookImportService())` and simulate
  /// any outcome (success, cancellation, failure) without ever touching a
  /// real device file picker. This is called "dependency injection," and
  /// this constructor-based version of it is the simplest form of it.
  final BookImportService _importService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Whether an import is currently in progress. This is the ONLY mutable
  /// state this screen holds, and it exists for exactly one reason: to
  /// tell `ImportBookButton` whether to show its spinner.
  bool _isImporting = false;

  Future<void> _handleImportPressed() async {
    setState(() => _isImporting = true);

    // STABILITY PATCH: BookImportService.pickBook() now guarantees it
    // never throws — every failure it can hit is already converted into
    // a BookImportFailure. This try/catch is a second, deliberately
    // redundant safety net, not a sign we don't trust that guarantee:
    // `_importService` is an injected dependency (see the constructor
    // above), so nothing at compile time stops a future test, or a
    // future second implementation, from throwing anyway. Catching here
    // too means THIS screen's core promise — the button never gets
    // stuck spinning — holds regardless of what's injected.
    BookImportResult result;
    try {
      result = await widget._importService.pickBook();
    } catch (_) {
      result = const BookImportFailure(AppStrings.importGenericError);
    }

    // Guard: if this screen has been removed from the widget tree while
    // we were awaiting the file picker (e.g. the user navigated away),
    // `context` is no longer safe to use. Every `await` followed by
    // `context` use needs this check — it's one of Flutter's most common
    // sources of runtime crashes when skipped.
    if (!mounted) return;

    setState(() => _isImporting = false);

    // `switch` over a sealed class: Dart's analyzer knows
    // BookImportResult has EXACTLY these four subtypes, so this switch is
    // "exhaustive" — if a fifth outcome is ever added to the sealed
    // class and a case for it isn't added here, this won't compile. No
    // `default:` branch is needed, or even allowed to silently swallow a
    // forgotten case.
    switch (result) {
      case BookImportSuccess(:final book):
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
        );
      case BookImportCancelled():
        // Deliberately does nothing. Cancelling is a normal outcome, not
        // something that deserves an error message or any feedback at all.
        break;
      case BookImportUnsupportedFormat(:final extension):
        AppSnackbar.showError(
          context,
          AppStrings.unsupportedFormatMessage(extension),
        );
      case BookImportFailure(:final message):
        AppSnackbar.showError(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTitle),
      ),
      // SafeArea keeps our content clear of notches, the status bar, and
      // other system UI cutouts on real Android devices.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const _WelcomeIllustration(),
              // Spacer flexibly consumes all remaining vertical space,
              // pushing the text + button block down towards the bottom
              // of the screen — a common, comfortable layout for a
              // single-primary-action screen.
              const Spacer(),
              Text(
                AppStrings.welcomeHeading,
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.welcomeSubtitle,
                style: AppTextStyles.subheading,
              ),
              const SizedBox(height: 32),
              ImportBookButton(
                isLoading: _isImporting,
                onPressed: _handleImportPressed,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// A simple decorative circle + icon standing in for a book illustration.
///
/// Kept as a PRIVATE widget (leading underscore `_`) because it is purely
/// an implementation detail of HomeScreen — no other screen needs it, so
/// there's no reason to expose it outside this file.
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.auto_stories_outlined,
          size: 84,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
