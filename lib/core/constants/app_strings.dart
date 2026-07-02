/// Centralized user-facing text.
///
/// WHY THIS FILE EXISTS:
/// Hard-coding strings like "Import Book" directly inside widgets means
/// that later — when we add multi-language support via
/// `flutter_localizations`, or just want to fix a typo used in five
/// places — we'd have to search the entire codebase. Keeping strings here
/// means ONE place to update, and this file becomes the natural spot to
/// plug in localization later without restructuring anything.
class AppStrings {
  AppStrings._();

  static const String appName = 'E-Book Reader';
  static const String homeTitle = 'E-Book Reader';

  static const String welcomeHeading = 'Welcome to your\nreading space';
  static const String welcomeSubtitle =
      'Import an e-book from your device and let us read it aloud for '
      'you — word by word, at your own pace.';

  static const String importButtonLabel = 'Import Book';

  static const String comingSoonMessage =
      'File picker will be connected in Module 2 🚀';
}
