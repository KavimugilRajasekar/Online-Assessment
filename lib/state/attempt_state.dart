import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/attempt.dart';
import '../models/result.dart';
import '../services/attempt_service.dart';
import '../services/attempt_store.dart';

enum SubmitState { idle, submitting, done, error }
enum ConnectivityState { online, offline }

class _QueuedAnswer {
  final String attemptId;
  final Map<String, dynamic> payload;
  int retryCount = 0;
  _QueuedAnswer(this.attemptId, this.payload);
}

class AttemptState extends ChangeNotifier {
  Attempt? attempt;
  QuizResult? result;
  SubmitState submitState = SubmitState.idle;
  ConnectivityState connectivity = ConnectivityState.online;
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

  // Offline answer queue
  final List<_QueuedAnswer> _queue = [];
  Timer? _retryTimer;

  // Auto-submit retry (used when submit() fails due to network)
  Timer? _submitRetryTimer;
  int _submitRetryCount = 0;
  static const int _maxSubmitRetries = 10;

  // Security & Proctoring
  int violationCount = 0;
  static const int maxViolations = 3;
  String? lastViolationReason;

  bool get isSubmitBlocked =>
      _queue.isNotEmpty || submitState == SubmitState.submitting;
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

  // ── MCQ answers ──────────────────────────────────────────────────────────────

  void selectSingleChoice(String questionId, String choiceId) {
    selectedChoices[questionId] = [choiceId];
    notifyListeners();
    _enqueueAnswer(questionId, selectedChoiceIds: [choiceId]);
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
    _enqueueAnswer(questionId, selectedChoiceIds: current);
  }

  // ── Code answers ─────────────────────────────────────────────────────────────

  void updateCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    notifyListeners();
  }

  void saveCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    _enqueueAnswer(questionId, codeText: code);
  }

  // ── Answer queue + retry ─────────────────────────────────────────────────────

  void _enqueueAnswer(String questionId,
      {List<String>? selectedChoiceIds, String? codeText}) {
    if (attempt == null) return;
    final payload = <String, dynamic>{'question_id': questionId};
    if (selectedChoiceIds != null) {
      payload['selected_choice_ids'] = selectedChoiceIds;
    }
    if (codeText != null) payload['code_text'] = codeText;
    _queue.removeWhere((q) => q.payload['question_id'] == questionId);
    _queue.add(_QueuedAnswer(attempt!.id, payload));
    notifyListeners();
    _flushQueue();
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty) return;
    connectivity = ConnectivityState.online;
    while (_queue.isNotEmpty) {
      final item = _queue.first;
      try {
        await AttemptService.instance
            .upsertAnswer(item.attemptId, item.payload);
        _queue.removeAt(0);
        notifyListeners();
      } catch (_) {
        connectivity = ConnectivityState.offline;
        notifyListeners();
        item.retryCount++;
        final delay =
            Duration(seconds: (1 << item.retryCount).clamp(1, 30));
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, _flushQueue);
        return;
      }
    }
    connectivity = ConnectivityState.online;
    notifyListeners();
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  /// Full submit from the UI (manual Submit button or auto-submit on timer/
  /// violations). Flushes the answer queue first, then calls the submit
  /// endpoint. If the network call fails, schedules automatic retries with
  /// exponential backoff so the admin panel eventually sees the attempt as
  /// submitted even if the user closes the app right after.
  Future<QuizResult?> submit() async {
    if (attempt == null) return null;
    final attemptId = attempt!.id;

    submitState = SubmitState.submitting;
    notifyListeners();

    // Flush queued answers best-effort before submitting.
    _retryTimer?.cancel();
    try {
      await _flushQueueImmediate();
    } catch (_) {
      // Submit anyway — server grades whatever answers it received.
    }

    try {
      result = await AttemptService.instance.submit(attemptId);
      await AttemptStore.instance.save(
        attempt?.quizId ?? '',
        attemptId,
      ); // keep the record so result screen can load it
      _timer?.cancel();
      _cancelSubmitRetry();
      submitState = SubmitState.done;
      attempt = null;
      notifyListeners();
      return result;
    } catch (e) {
      // Network / 5xx — schedule retry so the server eventually gets the
      // submit even if the user closes the app right now.
      submitState = SubmitState.error;
      errorMessage = e.toString();
      notifyListeners();
      _scheduleSubmitRetry(attemptId);
      return null;
    }
  }

  /// Retries the submit endpoint for [attemptId] with exponential backoff
  /// (2s, 4s, 8s … capped at 60s) up to [_maxSubmitRetries] attempts.
  /// Called automatically when [submit()] hits a network error.
  /// Also called by [reconcileStaleAttempt] on app resume.
  void _scheduleSubmitRetry(String attemptId) {
    _cancelSubmitRetry();
    if (_submitRetryCount >= _maxSubmitRetries) return;
    final delay =
        Duration(seconds: (1 << _submitRetryCount).clamp(2, 60));
    _submitRetryCount++;
    _submitRetryTimer = Timer(delay, () async {
      try {
        final accepted =
            await AttemptService.instance.submitById(attemptId);
        if (accepted) {
          // Server accepted — we're done.
          submitState = SubmitState.done;
          _cancelSubmitRetry();
          notifyListeners();
        } else {
          // 4xx — already submitted or deleted; stop retrying.
          submitState = SubmitState.done;
          _cancelSubmitRetry();
          notifyListeners();
        }
      } catch (_) {
        // Still failing — retry again.
        _scheduleSubmitRetry(attemptId);
      }
    });
  }

  void _cancelSubmitRetry() {
    _submitRetryTimer?.cancel();
    _submitRetryTimer = null;
    _submitRetryCount = 0;
  }

  Future<void> _flushQueueImmediate() async {
    for (final item in List.from(_queue)) {
      await AttemptService.instance
          .upsertAnswer(item.attemptId, item.payload);
      _queue.remove(item);
    }
  }

  Future<void> autoSubmit() async {
    await submit();
  }

  // ── Stale-attempt reconciler ─────────────────────────────────────────────────

  /// Called from HomeScreen on every load (and on app resume).
  ///
  /// Scenario: user started a quiz, the app was killed or the timer fired
  /// while offline, so the server never received the submit — admin panel
  /// still shows the attempt as "in_progress".
  ///
  /// Strategy:
  ///   1. For every (quizId, attemptId) pair stored in AttemptStore, ask
  ///      the server for the attempt status.
  ///   2. If the server already has it as submitted/expired → just clean up
  ///      local storage (nothing to do).
  ///   3. If it's still in_progress → fire submitById(). Retry with backoff
  ///      on network errors. Stop on 4xx (already handled server-side).
  ///
  /// Runs silently — no loading state is shown to the user.
  Future<void> reconcileStaleAttempts() async {
    // Don't interfere while the user is actively in a quiz.
    if (attempt != null) return;

    final attemptedIds =
        await AttemptStore.instance.getAttemptedQuizIds();
    if (attemptedIds.isEmpty) return;

    for (final quizId in attemptedIds) {
      final attemptId = await AttemptStore.instance.get(quizId);
      if (attemptId == null) continue;

      try {
        // Fetch current status from server.
        final serverAttempt =
            await AttemptService.instance.getAttempt(attemptId);

        if (serverAttempt.status == AttemptStatus.submitted ||
            serverAttempt.status == AttemptStatus.expired) {
          // Already finalised server-side — nothing to do.
          continue;
        }

        // Still in_progress on the server — submit it now.
        await _submitStaleAttempt(attemptId, quizId);
      } catch (e) {
        // getAttempt() failed (network / 404).
        // 404 means the attempt or quiz was deleted — clean up and move on.
        if (e is Exception && e.toString().contains('404')) {
          await AttemptStore.instance.remove(quizId);
        }
        // For other errors (network down) try submitting blind — the server
        // will ignore it if already submitted.
        else {
          await _submitStaleAttempt(attemptId, quizId);
        }
      }
    }
  }

  /// Submits [attemptId] and removes the local store entry on success.
  /// Schedules a retry via [_scheduleSubmitRetry] on transient failures.
  Future<void> _submitStaleAttempt(
      String attemptId, String quizId) async {
    try {
      final accepted =
          await AttemptService.instance.submitById(attemptId);
      if (accepted) {
        // Server accepted the late submit — keep the store entry so the
        // result screen can still load, but mark retry as done.
        _cancelSubmitRetry();
      }
      // false = 4xx (already submitted/not found) — nothing to retry.
    } catch (_) {
      // Transient network error — schedule retry in background.
      _scheduleSubmitRetry(attemptId);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────────

  void clear() {
    _timer?.cancel();
    _retryTimer?.cancel();
    _cancelSubmitRetry();
    attempt = null;
    result = null;
    submitState = SubmitState.idle;
    selectedChoices.clear();
    codeAnswers.clear();
    _queue.clear();
    currentQuestionIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    _cancelSubmitRetry();
    super.dispose();
  }
}
