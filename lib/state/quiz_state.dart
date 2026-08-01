import 'package:flutter/foundation.dart';
import '../models/quiz.dart';
import '../models/topic.dart';
import '../services/quiz_service.dart';
import '../services/attempt_store.dart';

enum QuizLoadState { idle, loading, loaded, error }

class QuizState extends ChangeNotifier {
  List<Quiz> quizzes = [];
  List<Topic> topics = [];
  Quiz? selectedQuiz;
  QuizLoadState loadState = QuizLoadState.idle;
  String? errorMessage;

  /// All quiz IDs attempted on this device that haven't had their
  /// answer key published yet. A Set so any number of quizzes can be
  /// tracked simultaneously.
  final Set<String> _attemptedQuizIds = {};

  /// Returns true when [quizId] was attempted on this device AND the
  /// admin has not yet published the answer key for it.
  bool isAttempted(String quizId) => _attemptedQuizIds.contains(quizId);

  /// Called the instant "Start Assessment" is tapped.
  /// Synchronous — sets the flag in memory immediately so the card is
  /// greyed out the moment the user returns to the home screen.
  void markAttempted(String quizId) {
    if (_attemptedQuizIds.add(quizId)) {
      notifyListeners();
    }
  }

  /// Loads quizzes from the API and syncs the locally-stored attempted
  /// IDs in a single async operation → one notifyListeners() call,
  /// no race between two separate futures.
  Future<void> loadQuizzes({bool silent = false}) async {
    // Read SharedPreferences first so attempted flags are populated
    // before the network response arrives (covers cold-start / app restart).
    final stored = await AttemptStore.instance.getAttemptedQuizIds();
    _attemptedQuizIds.addAll(stored);

    if (!silent && quizzes.isEmpty) {
      loadState = QuizLoadState.loading;
      errorMessage = null;
      notifyListeners();
    }

    try {
      final fresh = await QuizService.instance.listQuizzes();
      quizzes = fresh;

      // Build a set of live quiz IDs from the API response.
      final liveIds = fresh.map((q) => q.id).toSet();

      // 1. If the admin deleted a quiz this device attempted, remove it
      //    from local storage so the user isn't permanently locked out.
      final deleted = _attemptedQuizIds.difference(liveIds);
      for (final id in deleted) {
        _attemptedQuizIds.remove(id);
        await AttemptStore.instance.remove(id);
      }

      // 2. If a quiz this device attempted now has its answer key posted,
      //    remove it from the attempted set so the card becomes interactive
      //    (green "Answer Key Available") instead of staying greyed out.
      for (final q in fresh) {
        if (q.answersPosted && _attemptedQuizIds.contains(q.id)) {
          _attemptedQuizIds.remove(q.id);
          // Keep the attempt record in AttemptStore so the result screen
          // can still load — just don't grey out the card anymore.
        }
      }

      loadState = QuizLoadState.loaded;
      errorMessage = null;
    } catch (e) {
      if (quizzes.isEmpty) {
        loadState = QuizLoadState.error;
        errorMessage = e.toString();
      }
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
