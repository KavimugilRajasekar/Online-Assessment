import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/attempt.dart';
import '../models/answer.dart';
import '../models/result.dart';
import '../services/attempt_service.dart';
import '../services/attempt_store.dart';

enum SubmitState { idle, submitting, done, error }

class AttemptState extends ChangeNotifier {
  Attempt? attempt;
  QuizResult? result;
  SubmitState submitState = SubmitState.idle;
  String? errorMessage;
  int currentQuestionIndex = 0;

  // question_id -> selected choice ids (for MCQ)
  final Map<String, List<String>> selectedChoices = {};
  // question_id -> code text (for coding)
  final Map<String, String> codeAnswers = {};
  // Flagged questions set
  final Set<String> flaggedQuestions = {};

  // Timer
  Timer? _timer;
  int remainingSeconds = 0;
  int totalSeconds = 0;
  bool _autoSubmitted = false;

  // Background submit retry (fires after the user already sees the result)
  Timer? _submitRetryTimer;
  int _submitRetryCount = 0;
  static const int _maxSubmitRetries = 10;

  // Security & Proctoring
  int violationCount = 0;
  static const int maxViolations = 3;
  String? lastViolationReason;

  bool get isSubmitBlocked => submitState == SubmitState.submitting;
  bool get hasActiveAttempt =>
      attempt != null && attempt!.status == AttemptStatus.inProgress;

  // ── Flagging ────────────────────────────────────────────────────────────────

  void toggleFlagged(String questionId) {
    if (flaggedQuestions.contains(questionId)) {
      flaggedQuestions.remove(questionId);
    } else {
      flaggedQuestions.add(questionId);
    }
    notifyListeners();
  }

  // ── Violations ──────────────────────────────────────────────────────────────

  void recordViolation(String reason) {
    if (!hasActiveAttempt) return;
    violationCount++;
    lastViolationReason = reason;

    final penaltySeconds =
        (remainingSeconds > 0) ? (remainingSeconds ~/ 6) : 30;
    remainingSeconds =
        (remainingSeconds - (penaltySeconds > 0 ? penaltySeconds : 30))
            .clamp(0, remainingSeconds);

    notifyListeners();
    if (violationCount >= maxViolations && !_autoSubmitted) {
      _autoSubmitted = true;
      autoSubmit();
    }
  }

  // ── Attempt setup ────────────────────────────────────────────────────────────

  void setAttempt(Attempt a) {
    attempt = a;
    _autoSubmitted = false;
    submitState = SubmitState.idle;
    errorMessage = null;
    violationCount = 0;
    lastViolationReason = null;
    selectedChoices.clear();
    codeAnswers.clear();
    flaggedQuestions.clear();
    currentQuestionIndex = 0;
    _cancelSubmitRetry();
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    if (attempt == null) return;
    final deadline = attempt!.deadlineDateTime;
    final started = attempt!.startedAtDateTime;
    remainingSeconds =
        deadline.difference(DateTime.now().toUtc()).inSeconds;
    if (remainingSeconds < 0) remainingSeconds = 0;
    totalSeconds = deadline.difference(started).inSeconds.abs();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remainingSeconds > 0) {
        remainingSeconds--;
        notifyListeners();
      } else if (!_autoSubmitted) {
        _autoSubmitted = true;
        autoSubmit();
      }
    });
  }

  void goToQuestion(int index) {
    currentQuestionIndex = index;
    notifyListeners();
  }

  // ── MCQ answers — stored locally only, never pushed on tap ──────────────────

  void selectSingleChoice(String questionId, String choiceId) {
    selectedChoices[questionId] = [choiceId];
    notifyListeners();
  }

  void toggleMultiChoice(String questionId, String choiceId) {
    final current = List<String>.from(selectedChoices[questionId] ?? []);
    if (current.contains(choiceId)) {
      current.remove(choiceId);
    } else {
      current.add(choiceId);
    }
    selectedChoices[questionId] = current;
    notifyListeners();
  }

  // ── Code answers — stored locally only ──────────────────────────────────────

  void updateCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    notifyListeners();
  }

  /// Called from the coding screen's Save button — same as updateCodeAnswer,
  /// kept as a named method so call-sites don't need to change.
  void saveCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    notifyListeners();
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  /// Builds the list of [Answer] objects from whatever the user selected/typed.
  List<Answer> _buildAnswers() {
    if (attempt == null) return [];
    final answers = <Answer>[];
    for (final q in attempt!.questions) {
      final choiceIds = selectedChoices[q.id] ?? [];
      final code = codeAnswers[q.id] ?? '';
      if (choiceIds.isNotEmpty || code.isNotEmpty) {
        answers.add(Answer(
          questionId: q.id,
          selectedChoiceIds: choiceIds,
          codeText: code,
          marksAwarded: 0, // server fills this in
        ));
      }
    }
    return answers;
  }

  /// Submits the attempt.
  ///
  /// Flow:
  ///   1. Compute the result locally so the UI can navigate to the result
  ///      screen instantly — no network wait before the user sees their score.
  ///   2. Push all answers + submit to the server in the background.
  ///      Retries with exponential backoff up to [_maxSubmitRetries] times so
  ///      the admin panel eventually sees the attempt as submitted.
  ///
  /// Returns the locally-computed [QuizResult] immediately (never null unless
  /// there is no active attempt).
  QuizResult? submitAndPush() {
    if (attempt == null) return null;

    _timer?.cancel();
    submitState = SubmitState.submitting;
    notifyListeners();

    final attemptId = attempt!.id;
    final quizId = attempt!.quizId;
    final answers = _buildAnswers();
    final localResult = _computeLocalResult(answers);

    // Store result so the result screen can read it immediately.
    result = localResult;

    // Clear attempt state — the quiz is over from the user's perspective.
    attempt = null;
    submitState = SubmitState.done;
    notifyListeners();

    // Save the attempt ID locally so reconcileStaleAttempts can clean up.
    AttemptStore.instance.save(quizId, attemptId);

    // Push to server silently in background.
    _pushToServer(attemptId, answers);

    return localResult;
  }

  /// Computes a [QuizResult] entirely from local data.
  ///
  /// Since the server withholds `is_correct` on choices during an active
  /// attempt, per-question correctness and marks are marked as pending
  /// (isCorrect = null, marksAwarded = 0). The server-side result (fetched
  /// by reconcileStaleAttempts or on next app open) will have the real grades.
  ///
  /// Total score shown is therefore 0 until the server confirms — the result
  /// screen handles this gracefully by showing "Pending" when score is 0.
  QuizResult _computeLocalResult(List<Answer> answers) {
    if (attempt == null) {
      return QuizResult(
        id: '',
        quizId: '',
        status: 'submitted',
        totalMarks: 0,
        score: 0,
        answers: [],
      );
    }

    final answerMap = {for (final a in answers) a.questionId: a};
    final answerResults = attempt!.questions.map((q) {
      final a = answerMap[q.id] ??
          Answer(
            questionId: q.id,
            selectedChoiceIds: [],
            codeText: '',
            marksAwarded: 0,
          );
      return AnswerResult(question: q, answer: a);
    }).toList();

    return QuizResult(
      id: '',
      quizId: attempt!.quizId,
      status: 'submitted',
      totalMarks: attempt!.totalMarks,
      score: 0, // server will confirm
      answers: answerResults,
    );
  }

  /// Pushes all answers then fires the submit endpoint in the background.
  /// Retries on transient failures with exponential backoff.
  Future<void> _pushToServer(String attemptId, List<Answer> answers) async {
    try {
      // Upsert every answer, then submit.
      for (final answer in answers) {
        await AttemptService.instance.upsertAnswer(
          attemptId,
          answer.toJson(),
        );
      }
      await AttemptService.instance.submit(attemptId);
      _cancelSubmitRetry();
    } catch (_) {
      // Transient failure — retry with backoff so the server eventually
      // receives the submit even if the user closes the app.
      _scheduleSubmitRetry(attemptId, answers);
    }
  }

  /// Auto-submit triggered by the countdown timer or proctoring violations.
  /// Uses the same submitAndPush() path so the logic is consistent.
  Future<void> autoSubmit() async {
    submitAndPush();
  }

  // ── Background retry ─────────────────────────────────────────────────────────

  void _scheduleSubmitRetry(String attemptId, List<Answer> answers) {
    _cancelSubmitRetry();
    if (_submitRetryCount >= _maxSubmitRetries) return;
    final delay = Duration(seconds: (1 << _submitRetryCount).clamp(2, 60));
    _submitRetryCount++;
    _submitRetryTimer = Timer(delay, () => _pushToServer(attemptId, answers));
  }

  void _cancelSubmitRetry() {
    _submitRetryTimer?.cancel();
    _submitRetryTimer = null;
    _submitRetryCount = 0;
  }

  // ── Stale-attempt reconciler ─────────────────────────────────────────────────

  /// Called from HomeScreen on every load (and on app resume).
  ///
  /// If the app was killed before the background push completed, the server
  /// still has the attempt as "in_progress". This reconciler fires submitById()
  /// for any locally-stored attempt IDs that the server hasn't finalised yet.
  Future<void> reconcileStaleAttempts() async {
    if (attempt != null) return; // don't interfere while quiz is active

    final attemptedIds = await AttemptStore.instance.getAttemptedQuizIds();
    if (attemptedIds.isEmpty) return;

    for (final quizId in attemptedIds) {
      final attemptId = await AttemptStore.instance.get(quizId);
      if (attemptId == null) continue;

      try {
        final serverAttempt =
            await AttemptService.instance.getAttempt(attemptId);
        if (serverAttempt.status == AttemptStatus.submitted ||
            serverAttempt.status == AttemptStatus.expired) {
          continue; // already finalised — nothing to do
        }
        await _submitStaleAttempt(attemptId, quizId);
      } catch (e) {
        if (e is Exception && e.toString().contains('404')) {
          await AttemptStore.instance.remove(quizId);
        } else {
          await _submitStaleAttempt(attemptId, quizId);
        }
      }
    }
  }

  Future<void> _submitStaleAttempt(String attemptId, String quizId) async {
    try {
      final accepted = await AttemptService.instance.submitById(attemptId);
      if (accepted) _cancelSubmitRetry();
    } catch (_) {
      // Schedule a single retry — _pushToServer retry chain handles the rest.
      _scheduleSubmitRetry(attemptId, []);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────────

  void clear() {
    _timer?.cancel();
    _cancelSubmitRetry();
    attempt = null;
    result = null;
    submitState = SubmitState.idle;
    selectedChoices.clear();
    codeAnswers.clear();
    currentQuestionIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelSubmitRetry();
    super.dispose();
  }
}
