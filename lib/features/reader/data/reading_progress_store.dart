import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/reading_progress.dart';

/// Persists and retrieves [ReadingProgress], one entry per book.
///
/// WHY THIS CLASS LIVES IN `data/`, NOT `domain/`:
/// Same reasoning as `BookImportService` and `TtsService`: this is the
/// ONLY file in the `reader` feature that imports
/// `package:shared_preferences` — a third-party plugin that talks to
/// platform-native persistent storage. If this app ever needed a
/// different storage backend (e.g. a proper database once it supports a
/// multi-book library — see the Module 3 architecture notes on this),
/// only this file would change.
///
/// WHY `SharedPreferencesAsync` (NOT `SharedPreferences.getInstance()`):
/// The package's own documentation now describes the older
/// `SharedPreferences` singleton API as legacy and slated for future
/// deprecation, explicitly recommending `SharedPreferencesAsync` for new
/// code. It also has no shared mutable cache to reason about — every
/// call talks directly to the platform, which is simpler to reason about
/// correctly for the small amount of data this class stores.
class ReadingProgressStore {
  ReadingProgressStore();

  static const String _keyPrefix = 'reading_progress::';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// Saves [progress], overwriting any previously saved progress for the
  /// same `progress.bookPath`.
  Future<void> save(ReadingProgress progress) async {
    final String json = jsonEncode({
      'characterOffset': progress.characterOffset,
      'lastReadAt': progress.lastReadAt.toIso8601String(),
    });
    await _prefs.setString(_keyFor(progress.bookPath), json);
  }

  /// Returns the saved progress for [bookPath], or `null` if none exists
  /// — including if a previously-saved value can't be parsed. A corrupt
  /// or unexpected stored value is treated as "no saved progress" rather
  /// than allowed to crash the Reader screen over a persistence detail;
  /// the worst case is the user simply doesn't get offered a resume
  /// prompt they otherwise would have.
  Future<ReadingProgress?> load(String bookPath) async {
    final String? raw = await _prefs.getString(_keyFor(bookPath));
    if (raw == null) return null;

    try {
      final Map<String, dynamic> map =
          jsonDecode(raw) as Map<String, dynamic>;
      return ReadingProgress(
        bookPath: bookPath,
        characterOffset: map['characterOffset'] as int,
        lastReadAt: DateTime.parse(map['lastReadAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Clears saved progress for [bookPath] — called once a book is
  /// finished, since there's nothing left to resume.
  Future<void> clear(String bookPath) async {
    await _prefs.remove(_keyFor(bookPath));
  }

  String _keyFor(String bookPath) => '$_keyPrefix$bookPath';
}
