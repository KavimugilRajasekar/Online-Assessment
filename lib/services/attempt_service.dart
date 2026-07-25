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
    return QuizResult.fromJson(data as Map<String, dynamic>);
  }

  Future<QuizResult> getResult(String attemptId) async {
    final data = await ApiClient.instance.get('/api/attempts/$attemptId/result/');
    return QuizResult.fromJson(data as Map<String, dynamic>);
  }
}
