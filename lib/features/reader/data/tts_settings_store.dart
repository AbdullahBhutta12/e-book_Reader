import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/tts_settings.dart';

/// Persists and retrieves the user's [TtsSettings] — one saved
/// preference, shared across every book.
///
/// WHY THIS IS A SEPARATE CLASS FROM `ReadingProgressStore` (rather than
/// folding settings into that same store): they're genuinely different
/// concerns that happen to share a storage mechanism — one entry per
/// BOOK versus one entry, period, for the whole app. Keeping them
/// separate means either one's key scheme, load/save shape, or future
/// evolution (e.g. adding a "reset to defaults" method here) never has
/// to worry about the other's. Same reasoning `TextExtractorFactory` and
/// `TtsService` already follow: one class, one job.
///
/// WHY `SharedPreferencesAsync` (NOT `SharedPreferences.getInstance()`):
/// same reasoning as `ReadingProgressStore` — the package's own docs
/// describe the older singleton API as legacy and slated for future
/// deprecation.
class TtsSettingsStore {
  TtsSettingsStore();

  static const String _key = 'tts_settings';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<void> save(TtsSettings settings) async {
    final String json = jsonEncode({
      'speechRate': settings.speechRate,
      'pitch': settings.pitch,
    });
    await _prefs.setString(_key, json);
  }

  /// Returns the saved settings, or `null` if none have ever been saved
  /// — including if a previously-saved value can't be parsed, treated
  /// the same as "never saved" rather than allowed to crash the Reader
  /// screen over a persistence detail (same defensive reasoning as
  /// `ReadingProgressStore.load`).
  Future<TtsSettings?> load() async {
    final String? raw = await _prefs.getString(_key);
    if (raw == null) return null;

    try {
      final Map<String, dynamic> map =
          jsonDecode(raw) as Map<String, dynamic>;
      return TtsSettings(
        speechRate: (map['speechRate'] as num).toDouble(),
        pitch: (map['pitch'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
