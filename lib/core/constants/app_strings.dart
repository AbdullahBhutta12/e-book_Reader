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

  // --- Import feedback -----------------------------------------------
  // AppStrings.comingSoonMessage from Module 1 has been removed: the
  // import button is now fully functional, so that placeholder string is
  // dead code. Keeping unused strings around is clutter a future reader
  // has to figure out is safe to ignore.

  static const String importGenericError =
      'Something went wrong while importing your file. Please try again.';

  /// Takes the raw extension so the message can name it specifically,
  /// e.g. "Unsupported file type: .mobi".
  static String unsupportedFormatMessage(String extension) =>
      'Unsupported file type: .$extension\n'
      'Supported formats: PDF, EPUB, TXT.';

  // --- Reader screen: book info sheet (Module 2's metadata view, now
  // shown as an on-demand sheet rather than the whole screen) -----------
  static const String bookInfoSheetTitle = 'Book Details';
  static const String labelFileName = 'File Name';
  static const String labelFileSize = 'File Size';
  static const String labelFilePath = 'File Path';
  static const String labelFileExtension = 'File Extension';
  static const String bookInfoButtonTooltip = 'Book details';

  // --- Reader screen: content loading states ----------------------------
  static const String readerLoadingMessage = 'Opening your book…';

  static const String readerEmptyBookTitle = 'Nothing to read yet';
  static const String readerEmptyBookMessage =
      'This file doesn\'t contain any readable text.';

  static const String readerUnsupportedFormatTitle =
      'This format isn\'t supported for reading yet';

  /// Takes the raw extension so the message can name it specifically.
  static String readerUnsupportedFormatBody(String extension) =>
      '.$extension files can be imported, but reading them aloud isn\'t '
      'supported in this version yet. TXT files are fully supported — '
      'PDF and EPUB support is planned for a future update.';

  static const String readerLoadFailureTitle = 'Couldn\'t open this book';
  static const String readerLoadFailureMessage =
      'This book could not be opened. It may have been moved, deleted, '
      'or is not readable right now.';
}
