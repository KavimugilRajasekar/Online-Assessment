import '../models/attempt.dart';
import '../models/result.dart';
import 'api_client.dart';

class AttemptService {
  AttemptService._();
  static final AttemptService instance = AttemptService._();

  Future<Attempt> startAttempt(String quizId, {String? candidateName, String? candidateId}) async {
    final data = await ApiClient.instance.post('/api/quizzes/$quizId/attempts/', {
      'candidate_name': ?candidateName,
      'candidate_id': ?candidateId,
    });
    return Attempt.fromJson(data as Map<String, dynamic>);
  }

  /// Returns existing attempt on 409.
  Future<Attempt> startOrResumeAttempt(String quizId, {String? candidateName, String? candidateId}) async {
    try {
      return await startAttempt(quizId, candidateName: candidateName, candidateId: candidateId);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        final attemptData = e.body?['attempt'] as Map<String, dynamic>?;
        if (attemptData != null) return Attempt.fromJson(attemptData);
      }
      rethrow;
    }
  }

  Future<Attempt> getAttempt(String attemptId) async {
    final data = await ApiClient.instance.get('/api/attempts/$attemptId/');
    return Attempt.fromJson(data as Map<String, dynamic>);
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
    if (data is Map<String, dynamic>) {
      // Try direct parse
      if (data.containsKey('id') || data.containsKey('score')) {
        return QuizResult.fromJson(data);
      }
      // Wrapped response — try common envelope keys
      for (final key in ['result', 'attempt', 'data']) {
        final inner = data[key];
        if (inner is Map<String, dynamic>) {
          return QuizResult.fromJson(inner);
        }
      }
      // Still a map but no recognised structure — best effort
      return QuizResult.fromJson(data);
    }
    // Unexpected type — fall back to fetching the result
    return getResult(attemptId);
  }

  Future<QuizResult> getResult(String attemptId) async {
    final data = await ApiClient.instance.get('/api/attempts/$attemptId/result/');
    return QuizResult.fromJson(data as Map<String, dynamic>);
  }
}
