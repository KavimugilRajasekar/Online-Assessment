import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Current storage key — holds a JSON map of { quizId: attemptId }
const _kAttemptsMap = 'oa_attempts_map';

// Legacy keys from the old single-attempt implementation.
// Read once on first launch so existing users don't lose their state.
const _kLegacyAttemptId = 'oa_attempt_id';
const _kLegacyQuizId = 'oa_quiz_id';

class AttemptStore {
  AttemptStore._();
  static final AttemptStore instance = AttemptStore._();

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Map<String, String>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_kAttemptsMap);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }

    // ── One-time migration from legacy single-key storage ──────────────────
    final legacyQuizId = prefs.getString(_kLegacyQuizId);
    final legacyAttemptId = prefs.getString(_kLegacyAttemptId);
    if (legacyQuizId != null && legacyAttemptId != null) {
      final migrated = {legacyQuizId: legacyAttemptId};
      await prefs.setString(_kAttemptsMap, jsonEncode(migrated));
      await prefs.remove(_kLegacyQuizId);
      await prefs.remove(_kLegacyAttemptId);
      return migrated;
    }

    return {};
  }

  Future<void> _writeMap(
      SharedPreferences prefs, Map<String, String> map) async {
    await prefs.setString(_kAttemptsMap, jsonEncode(map));
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Persist [attemptId] for [quizId]. Keeps all previously stored entries.
  Future<void> save(String quizId, String attemptId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    map[quizId] = attemptId;
    await _writeMap(prefs, map);
  }

  /// Returns the attempt ID for [quizId], or null if not found.
  Future<String?> get(String quizId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    return map[quizId];
  }

  /// Returns the full set of quiz IDs that have been attempted on this device.
  Future<Set<String>> getAttemptedQuizIds() async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    return map.keys.toSet();
  }

  /// Removes a single quiz entry (e.g. when the admin deletes that quiz).
  Future<void> remove(String quizId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    if (map.remove(quizId) != null) {
      await _writeMap(prefs, map);
    }
  }

  /// Clears all stored attempts.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAttemptsMap);
    // Also clear legacy keys in case they still exist.
    await prefs.remove(_kLegacyAttemptId);
    await prefs.remove(_kLegacyQuizId);
  }
}
