import 'package:flutter/foundation.dart';
import '../models/quiz.dart';
import '../models/topic.dart';
import '../services/quiz_service.dart';

enum QuizLoadState { idle, loading, loaded, error }

class QuizState extends ChangeNotifier {
  List<Quiz> quizzes = [];
  List<Topic> topics = [];
  Quiz? selectedQuiz;
  QuizLoadState loadState = QuizLoadState.idle;
  String? errorMessage;

  Future<void> loadQuizzes() async {
    loadState = QuizLoadState.loading;
    errorMessage = null;
    notifyListeners();
    try {
      quizzes = await QuizService.instance.listQuizzes();
      loadState = QuizLoadState.loaded;
    } catch (e) {
      loadState = QuizLoadState.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadTopics(String quizId) async {
    loadState = QuizLoadState.loading;
    notifyListeners();
    try {
      topics = await QuizService.instance.getTopics(quizId);
      loadState = QuizLoadState.loaded;
    } catch (e) {
      loadState = QuizLoadState.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  void selectQuiz(Quiz quiz) {
    selectedQuiz = quiz;
    notifyListeners();
  }
}
