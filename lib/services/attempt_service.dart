import '../models/attempt.dart';
import '../models/result.dart';
import 'api_client.dart';

class AttemptService {
  AttemptService._();
  static final AttemptService instance = AttemptService._();

  Future<Attempt> startAttempt(String quizId, {String? candidateName, String? candidateId}) async {
    final data = await ApiClient.instance.post('/api/quizzes/$quizId/attempts/', {
      'candidate_name': candidateName,
      'candidate_id': candidateId,
    });
    return Attempt.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  /// Returns existing attempt on 409.
  Future<Attempt> startOrResumeAttempt(String quizId, {String? candidateName, String? candidateId}) async {
    try {
      return await startAttempt(quizId, candidateName: candidateName, candidateId: candidateId);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        final attemptData = e.body?['attempt'];
        if (attemptData is Map) {
          return Attempt.fromJson(Map<String, dynamic>.from(attemptData));
        }
      }
      rethrow;
    }
  }

  Future<Attempt> getAttempt(String attemptId) async {
    final data = await ApiClient.instance.get('/api/attempts/$attemptId/');
    return Attempt.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  /// Returns true on success (204), throws on error.
  Future<void> upsertAnswer(String attemptId, Map<String, dynamic> answer) async {
    await ApiClient.instance.post('/api/attempts/$attemptId/answers/', answer);
  }

  Future<QuizResult> submit(String attemptId) async {
    final data = await ApiClient.instance.post('/api/attempts/$attemptId/submit/');
    return _parseResult(data, attemptId);
  }

  /// Parses a QuizResult from the raw API response, handling multiple formats:
  /// - Direct result map
  /// - Wrapped under 'result', 'attempt', or 'data' keys
  /// - Falls back to getResult() if parsing fails
  Future<QuizResult> _parseResult(dynamic data, String attemptId) async {
    if (data == null) {
      // 204 No Content — fetch result separately
      return getResult(attemptId);
    }
    if (data is Map) {
      final mapData = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data);
      // Try direct parse
      if (mapData.containsKey('id') || mapData.containsKey('score')) {
        return QuizResult.fromJson(mapData);
      }
      // Wrapped response — try common envelope keys
      for (final key in ['result', 'attempt', 'data']) {
        final inner = mapData[key];
        if (inner is Map) {
          final innerMap = inner is Map<String, dynamic>
              ? inner
              : Map<String, dynamic>.from(inner);
          return QuizResult.fromJson(innerMap);
        }
      }
      // Still a map but no recognised structure — best effort
      return QuizResult.fromJson(mapData);
    }
    // Unexpected type — fall back to fetching the result
    return getResult(attemptId);
  }

  Future<QuizResult> getResult(String attemptId) async {
    final data = await ApiClient.instance.get('/api/attempts/$attemptId/result/');
    return QuizResult.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  /// Submits an attempt purely by its ID — no in-memory [Attempt] object
  /// needed. Used by the stale-attempt reconciler on app resume / home load.
  ///
  /// Returns true  → server accepted the submit (2xx).
  /// Returns false → attempt was already submitted / not found (400, 404, 409)
  ///                  — caller should stop retrying and clean up local store.
  /// Throws        → network / 5xx error — caller should retry with backoff.
  Future<bool> submitById(String attemptId) async {
    try {
      await ApiClient.instance.post('/api/attempts/$attemptId/submit/');
      return true;
    } on ApiException catch (e) {
      // 400/404/409/410 all mean the server already handled this attempt —
      // no point retrying.
      if (e.statusCode == 400 ||
          e.statusCode == 404 ||
          e.statusCode == 409 ||
          e.statusCode == 410) {
        return false;
      }
      rethrow; // 5xx / timeout → let caller retry
    }
  }
}
