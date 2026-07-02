import 'package:flutter/material.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../widgets/import_book_button.dart';

/// The first screen the user sees when opening the app.
///
/// WHY StatelessWidget (and not StatefulWidget):
/// This screen currently holds no mutable state of its own — nothing here
/// needs to change and trigger a rebuild while the user looks at it. It's
/// a pure "given this context, render this UI" widget. Once we wire up
/// real file picking in Module 2 (which will need to show a loading
/// spinner while a file is being read), that's exactly the kind of change
/// that will push this screen towards holding state — but not yet, and we
/// don't add complexity before it's needed.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Handles the Import Book button tap.
  ///
  /// Module 1 only builds the UI shell — the real `file_picker` package
  /// integration happens in Module 2. Showing a SnackBar here is a REAL,
  /// working interaction for this stage of the app (not a placeholder):
  /// it honestly communicates to the user what the feature currently does.
  void _handleImportPressed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.comingSoonMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                onPressed: () => _handleImportPressed(context),
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
