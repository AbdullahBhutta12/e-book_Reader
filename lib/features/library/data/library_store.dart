import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../reader/domain/models/supported_book_format.dart';
import '../domain/models/library_book.dart';

/// Persists and retrieves the entire library as one JSON array.
///
/// WHY ONE JSON ARRAY UNDER ONE KEY (not an embedded database like
/// Hive/Isar): a personal book library is realistically tens to a few
/// hundred entries, and every operation the Library screen needs —
/// search is a substring filter, sort is a comparator — is naturally an
/// in-memory `List<LibraryBook>` operation, not a query a database
/// engine buys anything for. Reading and rewriting one small JSON blob
/// on each add/delete is imperceptible at this scale. The explicit
/// trigger to revisit this: if the library ever needs true relational
/// data (collections, tags) or reaches a scale where loading the whole
/// list becomes noticeable — not before.
///
/// WHY THIS IS ITS OWN CLASS, SEPARATE FROM `ReadingProgressStore`: one
/// entry per BOOK (this class) versus one entry, period, for the whole
/// app (`TtsSettingsStore`) versus one entry per book's READING POSITION
/// (`ReadingProgressStore`) are three genuinely different shapes of data
/// that happen to share a storage mechanism — the same "one class, one
/// job" separation this project has kept consistently since Module 2.
class LibraryStore {
  LibraryStore();

  static const String _key = 'library_books';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// Loads every library entry. Returns an empty list if nothing has
  /// ever been saved, or if the stored value isn't valid JSON at all.
  ///
  /// WHY A BAD INDIVIDUAL ENTRY DOESN'T DISCARD THE WHOLE LIBRARY: unlike
  /// `ReadingProgressStore`/`TtsSettingsStore` (which each parse ONE
  /// record and can safely treat any failure as "nothing saved"), this
  /// parses a LIST — one malformed entry (e.g. an unrecognized `format`
  /// string from some future edge case) failing to parse shouldn't cost
  /// the user their entire library. Each entry is parsed in its own
  /// try/catch; only that one entry is dropped if it fails.
  Future<List<LibraryBook>> loadAll() async {
    final String? raw = await _prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final List<dynamic> rawList = jsonDecode(raw) as List<dynamic>;
      return rawList
          .map((e) => _tryDecode(e as Map<String, dynamic>))
          .whereType<LibraryBook>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Saves the ENTIRE library, replacing whatever was there before.
  /// `LibraryController` always calls this with its complete, current
  /// in-memory list after any mutation — there's no separate
  /// add-one/remove-one persistence method, since the list is small
  /// enough (see this class's own doc comment) that rewriting the whole
  /// thing is simpler than reasoning about partial updates, with no real
  /// cost at this scale.
  Future<void> saveAll(List<LibraryBook> books) async {
    final String json = jsonEncode(books.map(_encode).toList());
    await _prefs.setString(_key, json);
  }

  Map<String, dynamic> _encode(LibraryBook book) => {
        'identityKey': book.identityKey,
        'name': book.name,
        'format': book.format.extension,
        'sizeInBytes': book.sizeInBytes,
        'storedPath': book.storedPath,
        'importedAt': book.importedAt.toIso8601String(),
        'lastOpenedAt': book.lastOpenedAt.toIso8601String(),
      };

  LibraryBook? _tryDecode(Map<String, dynamic> json) {
    try {
      final SupportedBookFormat? format =
          SupportedBookFormat.fromExtension(json['format'] as String);
      if (format == null) return null; // unrecognized — drop this entry

      return LibraryBook(
        identityKey: json['identityKey'] as String,
        name: json['name'] as String,
        format: format,
        sizeInBytes: json['sizeInBytes'] as int,
        storedPath: json['storedPath'] as String,
        importedAt: DateTime.parse(json['importedAt'] as String),
        lastOpenedAt: DateTime.parse(json['lastOpenedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
