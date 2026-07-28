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

  static const String readerNotYetReadableTitle =
      'This format isn\'t readable yet';

  /// Takes the raw extension so the message can name it specifically.
  ///
  /// STABILITY PATCH: reworded to explicitly say the file WAS recognized
  /// and imported successfully — earlier wording ("isn't supported for
  /// reading") could read as if the file itself were rejected or
  /// invalid, when in fact it's sitting safely in the user's library,
  /// recognized as a real book; we simply can't extract its text yet.
  static String readerNotYetReadableBody(String extension) =>
      'This .$extension file was recognized and imported successfully. '
      'Reading it aloud isn\'t supported in this version yet — TXT files '
      'are fully supported today, and PDF/EPUB support is planned for a '
      'future update.';

  static const String readerLoadFailureTitle = 'Couldn\'t open this book';
  static const String readerLoadFailureMessage =
      'This book could not be opened. It may have been moved, deleted, '
      'or is not readable right now.';

  // --- Text-to-speech: playback controls --------------------------------
  static const String ttsPlayLabel = 'Play';
  static const String ttsPauseLabel = 'Pause';
  static const String ttsStopLabel = 'Stop';

  // --- Text-to-speech: persistent "can't use it at all right now" states.
  // Shown inline in place of the control bar — these describe a standing
  // condition, not a one-off event, so a SnackBar would be the wrong tool
  // (it disappears; the condition doesn't).
  static const String ttsUnavailableMessage =
      'Text-to-speech isn\'t available on this device.';

  /// Takes the language code so the message can name it specifically.
  static String ttsUnsupportedLanguageMessage(String languageCode) =>
      'This device doesn\'t have the $languageCode voice installed for '
      'text-to-speech. Please install it from your device\'s language '
      'settings.';

  static const String ttsInitGenericError =
      'Text-to-speech failed to start. Please restart the app and try '
      'again.';

  // --- Text-to-speech: transient, one-off errors during playback. Shown
  // as a SnackBar (see AppSnackbar) since these describe a single event
  // that already happened, not an ongoing condition.
  static const String ttsPlaybackErrorMessage =
      'Something went wrong while reading this book aloud.';

  // --- Reading progress & resume (Module 6) ------------------------------
  static const String resumeDialogTitle = 'Resume reading?';
  static const String resumeDialogMessage =
      'You have unfinished progress in this book. Would you like to pick '
      'up where you left off, or start over from the beginning?';
  static const String resumeButtonLabel = 'Resume';
  static const String startOverButtonLabel = 'Start Over';

  // --- Playback settings (Module 7) ---------------------------------------
  static const String playbackSettingsButtonTooltip = 'Playback settings';
  static const String playbackSettingsTitle = 'Playback Settings';
  static const String speechRateLabel = 'Speech Rate';
  static const String pitchLabel = 'Pitch';

  // --- Library (Module 8) -------------------------------------------------
  static const String continueReadingLabel = 'Continue Reading';
  static const String libraryTitle = 'Your Library';
  static const String librarySearchHint = 'Search your library';
  static const String libraryEmptySearchMessage =
      'No books match your search.';
  static const String libraryFileMissingLabel =
      'File unavailable — tap the delete icon to remove it';
  static const String deleteBookButtonTooltip = 'Delete book';
  static const String deleteBookDialogTitle = 'Delete this book?';
  static const String deleteBookDialogMessage =
      'This removes the book and its reading progress from your library. '
      'This can\'t be undone.';
  static const String deleteButtonLabel = 'Delete';
  static const String cancelButtonLabel = 'Cancel';
  static const String sortButtonTooltip = 'Sort books';
  static const String sortByRecentlyOpened = 'Recently Opened';
  static const String sortByTitle = 'Title';
  static const String sortByRecentlyImported = 'Recently Imported';
}
