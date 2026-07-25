import '../models/quiz.dart';
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
}
