/// Every book file format this app currently knows how to open.
///
/// WHY AN ENUM INSTEAD OF A RAW `List<String>` OF EXTENSIONS:
/// A `List<String>` like `['pdf', 'epub', 'txt']` has no compiler backing —
/// typo `'epbu'` somewhere and Dart won't warn you. An enum gives us a
/// closed, named set of values. More importantly: anywhere in the app
/// where we `switch` on a `SupportedBookFormat` (for example, Module 3
/// choosing "how do I extract text from a PDF vs an EPUB vs a .txt?"),
/// Dart's *exhaustiveness checking* will raise a compile-time error if we
/// add a new format here and forget to handle it somewhere else. That's a
/// bug caught while writing the code, instead of discovered by a user.
///
/// WHY "ENHANCED ENUM" SYNTAX (a Dart 2.17+ / Dart 3 feature):
/// Older Dart enums could only be a bare list of names. Enhanced enums let
/// an enum value carry its own fields and constructor — here, each format
/// carries its own file extension string — so the extension and its enum
/// value can never drift apart or get looked up from a separate map.
enum SupportedBookFormat {
  pdf('pdf'),
  epub('epub'),
  plainText('txt');

  const SupportedBookFormat(this.extension);

  /// Lowercase extension with no leading dot, e.g. "pdf".
  final String extension;

  /// All supported extensions, ready to hand directly to file_picker's
  /// `allowedExtensions` parameter.
  static List<String> get allExtensions =>
      values.map((format) => format.extension).toList();

  /// Matches a raw extension string (as returned by file_picker) to one
  /// of our known formats. Returns `null` if it's not one we support —
  /// callers use that `null` to trigger the "unsupported format" error
  /// path rather than crashing on an unmatched format.
  static SupportedBookFormat? fromExtension(String extension) {
    final normalized = extension.toLowerCase();
    for (final format in values) {
      if (format.extension == normalized) return format;
    }
    return null;
  }
}
