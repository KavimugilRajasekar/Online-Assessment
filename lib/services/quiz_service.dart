import '../models/quiz.dart';
import '../models/question.dart';
import '../models/topic.dart';
import 'api_client.dart';

class QuizService {
  QuizService._();
  static final QuizService instance = QuizService._();

  Future<List<Quiz>> listQuizzes() async {
    final data = await ApiClient.instance.get('/api/quizzes/');
    return (data as List).map((e) => Quiz.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Topic>> getTopics(String quizId) async {
    final data = await ApiClient.instance.get('/api/quizzes/$quizId/topics/');
    final topics = (data as Map<String, dynamic>)['topics'] as List;
    return topics.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetches questions for a quiz including the answer key (is_correct on each
  /// choice). Used at Start Assessment time so the client can grade locally the
  /// moment the user submits, without a round-trip back to the server.
  ///
  /// Falls back gracefully: if the endpoint returns a list directly, a wrapped
  /// {"questions": [...]} map, or even an empty body, we handle all cases.
  Future<List<Question>> getQuestionsWithAnswers(String quizId) async {
    final data = await ApiClient.instance
        .get('/api/quizzes/$quizId/questions/?include_answers=true');

    List<dynamic> rawList;
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data);
      // Common envelope keys the server might use
      final inner = map['questions'] ?? map['data'] ?? map['results'];
      rawList = inner is List ? inner : [];
    } else {
      rawList = [];
    }

    return rawList
        .map((q) => Question.fromJson(q is Map<String, dynamic>
            ? q
            : (q is Map ? Map<String, dynamic>.from(q) : <String, dynamic>{})))
        .toList();
  }
}
