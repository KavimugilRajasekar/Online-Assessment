import 'package:shared_preferences/shared_preferences.dart';

const _kAttemptId = 'oa_attempt_id';
const _kQuizId = 'oa_quiz_id';

class AttemptStore {
  AttemptStore._();
  static final AttemptStore instance = AttemptStore._();

  Future<void> save(String quizId, String attemptId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQuizId, quizId);
    await prefs.setString(_kAttemptId, attemptId);
  }

  Future<String?> getAttemptId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAttemptId);
  }

  Future<String?> getQuizId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kQuizId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAttemptId);
    await prefs.remove(_kQuizId);
  }
}
