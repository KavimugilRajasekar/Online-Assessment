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

  // Timer
  Timer? _timer;
  int remainingSeconds = 0;
  bool _autoSubmitted = false;

  // Offline queue
  final List<_QueuedAnswer> _queue = [];
  Timer? _retryTimer;

  // Security & Proctoring
  int violationCount = 0;
  static const int maxViolations = 3;
  String? lastViolationReason;

  bool get isSubmitBlocked => _queue.isNotEmpty || submitState == SubmitState.submitting;
  bool get hasActiveAttempt => attempt != null && attempt!.status == AttemptStatus.inProgress;

  void recordViolation(String reason) {
    if (!hasActiveAttempt) return;
    violationCount++;
    lastViolationReason = reason;
    notifyListeners();
    if (violationCount >= maxViolations && !_autoSubmitted) {
      _autoSubmitted = true;
      autoSubmit();
    }
  }

  void setAttempt(Attempt a) {
    attempt = a;
    _autoSubmitted = false;
    submitState = SubmitState.idle;
    errorMessage = null;
    violationCount = 0;
    lastViolationReason = null;
    selectedChoices.clear();
    codeAnswers.clear();
    currentQuestionIndex = 0;

    // Restore any existing answers from the attempt detail (if resumed)
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    if (attempt == null) return;
    final deadline = attempt!.deadlineDateTime;
    remainingSeconds = deadline.difference(DateTime.now().toUtc()).inSeconds;
    if (remainingSeconds < 0) remainingSeconds = 0;
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

  // ---- MCQ Answer ----
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

  // ---- Code Answer ----
  void updateCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    // Debounced save is handled by the CodingScreen widget via a debounce Timer.
    // This just keeps in-memory state in sync.
    notifyListeners();
  }

  void saveCodeAnswer(String questionId, String code) {
    codeAnswers[questionId] = code;
    _enqueueAnswer(questionId, codeText: code);
  }

  // ---- Queue + Retry ----
  void _enqueueAnswer(String questionId, {List<String>? selectedChoiceIds, String? codeText}) {
    if (attempt == null) return;
    final payload = <String, dynamic>{'question_id': questionId};
    if (selectedChoiceIds != null) payload['selected_choice_ids'] = selectedChoiceIds;
    if (codeText != null) payload['code_text'] = codeText;
    // Remove existing queued answer for same question (replace)
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
        await AttemptService.instance.upsertAnswer(item.attemptId, item.payload);
        _queue.removeAt(0);
        notifyListeners();
      } catch (_) {
        connectivity = ConnectivityState.offline;
        notifyListeners();
        // Exponential backoff
        item.retryCount++;
        final delay = Duration(seconds: (1 << item.retryCount).clamp(1, 30));
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, _flushQueue);
        return;
      }
    }
    connectivity = ConnectivityState.online;
    notifyListeners();
  }

  // ---- Submit ----
  Future<QuizResult?> submit() async {
    if (attempt == null) return null;
    submitState = SubmitState.submitting;
    notifyListeners();
    // Wait for queue to drain (best-effort)
    _retryTimer?.cancel();
    // Try to flush immediately
    try {
      await _flushQueueImmediate();
    } catch (_) {
      // Queue couldn't flush — submit anyway; server will grade what it has
    }
    try {
      result = await AttemptService.instance.submit(attempt!.id);
      await AttemptStore.instance.clear();
      _timer?.cancel();
      submitState = SubmitState.done;
      attempt = null;
      notifyListeners();
      return result;
    } catch (e) {
      submitState = SubmitState.error;
      errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> _flushQueueImmediate() async {
    for (final item in List.from(_queue)) {
      await AttemptService.instance.upsertAnswer(item.attemptId, item.payload);
      _queue.remove(item);
    }
  }

  Future<void> autoSubmit() async {
    await submit();
  }

  void clear() {
    _timer?.cancel();
    _retryTimer?.cancel();
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
    super.dispose();
  }
}
