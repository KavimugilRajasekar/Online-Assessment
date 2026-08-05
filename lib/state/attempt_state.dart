import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/attempt.dart';
import '../models/answer.dart';
import '../models/choice.dart';
import '../models/question.dart';
import '../models/quiz.dart';
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

  // Per-question debounce timers for background answer push.
  // Keyed by stateKey (same as selectedChoices). A short delay lets the
  // user change their mind on multi-select without hammering the server.
  final Map<String, Timer> _pushDebounceTimers = {};

  // State keys that have been successfully upserted to the server.
  // At submit time only keys NOT in this set need re-upsert, saving
  // a full round-trip batch when answers were already pushed on selection.
  final Set<String> _pushedStateKeys = {};

  // Time tracking — captured at submit so the result screen can display it
  int timeUsedSeconds = 0;
  int quizTotalSeconds = 0;

  // Whether the background server push has completed successfully
  bool serverSyncDone = false;

  // Whether all retries were exhausted without a successful server sync
  bool serverSyncFailed = false;

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

  // ── Shuffle ──────────────────────────────────────────────────────────────────

  /// Applies client-side shuffle to [attempt] according to the [quiz] flags:
  ///
  /// - [Quiz.shuffleQuestions] → questions are shuffled **within each topic
  ///   group** so per-topic ordering in the quiz screen is still coherent.
  ///   The relative order of topic groups themselves is preserved.
  /// - [Quiz.shuffleChoices]   → choices on every MCQ question are shuffled
  ///   independently.
  ///
  /// Returns a new [Attempt] instance with the shuffled question list (and
  /// shuffled choice lists on each question). The original [attempt] object
  /// is not mutated.
  static Attempt applyShuffleToAttempt(Attempt attempt, Quiz quiz) {
    final rng = Random();

    // ── Step 1: collect questions grouped by topic, preserving topic order ──
    final Map<String, List<Question>> topicGroups = {};
    final List<String> topicOrder = [];

    for (final q in attempt.questions) {
      final tid = q.topicId.isNotEmpty ? q.topicId : '__default__';
      if (!topicGroups.containsKey(tid)) {
        topicGroups[tid] = [];
        topicOrder.add(tid);
      }
      topicGroups[tid]!.add(q);
    }

    // ── Step 2: optionally shuffle questions within each topic group ─────────
    if (quiz.shuffleQuestions) {
      for (final tid in topicOrder) {
        topicGroups[tid]!.shuffle(rng);
      }
    }

    // ── Step 3: optionally shuffle choices on every question ─────────────────
    List<Question> maybeShuffleChoices(List<Question> questions) {
      if (!quiz.shuffleChoices) return questions;
      return questions.map((q) {
        if (q.choices.isEmpty) return q;
        final shuffled = List<Choice>.from(q.choices)..shuffle(rng);
        return Question(
          id: q.id,
          qtype: q.qtype,
          text: q.text,
          code: q.code,
          marks: q.marks,
          choices: shuffled,
          starterCode: q.starterCode,
          language: q.language,
          explanation: q.explanation,
          topicId: q.topicId,
          topicName: q.topicName,
        );
      }).toList();
    }

    // ── Step 4: flatten back to a single ordered list ────────────────────────
    final shuffledQuestions = [
      for (final tid in topicOrder)
        ...maybeShuffleChoices(topicGroups[tid]!),
    ];

    // ── Step 5: rebuild the Attempt with the new question order ──────────────
    return Attempt(
      id: attempt.id,
      quizId: attempt.quizId,
      status: attempt.status,
      startedAt: attempt.startedAt,
      deadlineAt: attempt.deadlineAt,
      totalMarks: attempt.totalMarks,
      questionOrder: shuffledQuestions.map((q) => q.id).toList(),
      questions: shuffledQuestions,
    );
  }

  // ── Attempt setup ────────────────────────────────────────────────────────────

  /// Returns a copy of [a] whose questions are sorted to be topic-contiguous,
  /// preserving the original relative order within each topic group and the
  /// first-seen order of the topic groups themselves.
  ///
  /// If questions are already topic-contiguous (the common case after
  /// [applyShuffleToAttempt] or a well-ordered server response) this is a
  /// cheap no-op that returns [a] unchanged.
  static Attempt _withTopicOrder(Attempt a) {
    // Group by topicId, preserving first-seen topic order.
    final Map<String, List<Question>> groups = {};
    final List<String> topicOrder = [];
    for (final q in a.questions) {
      final tid = q.topicId.isNotEmpty ? q.topicId : '__default__';
      if (!groups.containsKey(tid)) {
        groups[tid] = [];
        topicOrder.add(tid);
      }
      groups[tid]!.add(q);
    }
    final reordered = [for (final tid in topicOrder) ...groups[tid]!];

    // Fast-path: already in the right order — avoid rebuilding the object.
    bool alreadyOrdered = true;
    for (int i = 0; i < reordered.length; i++) {
      if (reordered[i] != a.questions[i]) {
        alreadyOrdered = false;
        break;
      }
    }
    if (alreadyOrdered) return a;

    return Attempt(
      id: a.id,
      quizId: a.quizId,
      status: a.status,
      startedAt: a.startedAt,
      deadlineAt: a.deadlineAt,
      totalMarks: a.totalMarks,
      questionOrder: reordered.map((q) => q.id).toList(),
      questions: reordered,
    );
  }

  void setAttempt(Attempt a, {VoidCallback? onTimerExpired}) {
    _onAutoSubmitNavigate = onTimerExpired;
    // Reorder questions to be topic-contiguous so that the flat positional
    // index used by stateKeyFor / _buildAnswers always matches the
    // topic-grouped order the QuizScreen PageView and review screen show.
    // Without this, a server that returns questions interleaved across topics
    // (e.g. [Q_topicA, Q_topicB, Q_topicA]) would cause the PageView page-
    // index to diverge from the topic-offset globalIndex, writing state keys
    // that _buildAnswers can't find at submit time.
    attempt = _withTopicOrder(a);
    _autoSubmitted = false;
    submitState = SubmitState.idle;
    errorMessage = null;
    violationCount = 0;
    lastViolationReason = null;
    selectedChoices.clear();
    codeAnswers.clear();
    flaggedQuestions.clear();
    for (final t in _pushDebounceTimers.values) {
      t.cancel();
    }
    _pushDebounceTimers.clear();
    _pushedStateKeys.clear();
    currentQuestionIndex = 0;
    timeUsedSeconds = 0;
    quizTotalSeconds = 0;
    serverSyncDone = false;
    serverSyncFailed = false;
    _cancelSubmitRetry();
    _startTimer();
    notifyListeners();
  }

  void clearAutoSubmitCallback() {
    _onAutoSubmitNavigate = null;
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
        autoSubmit(onDone: _onAutoSubmitNavigate);
      }
    });
  }

  /// Set by QuizScreen to a navigation callback that fires immediately after
  /// autoSubmit completes. Using a callback avoids relying on postFrameCallback
  /// which can be missed during rapid state transitions from the timer.
  VoidCallback? _onAutoSubmitNavigate;

  void goToQuestion(int index) {
    currentQuestionIndex = index;
    notifyListeners();
  }

  // ── MCQ answers — stored locally only, never pushed on tap ──────────────────

  void selectSingleChoice(String questionId, String choiceId) {
    selectedChoices[questionId] = [choiceId];
    notifyListeners();
    // Push immediately — single-select is a final decision on tap.
    _schedulePush(questionId, immediate: true);
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
    // Debounced — user may tap several options in quick succession.
    _schedulePush(questionId);
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

  // ── Background per-answer push ───────────────────────────────────────────────

  /// Schedules a background upsert for the question identified by [stateKey].
  ///
  /// For single-choice questions the push fires immediately (no debounce
  /// needed — the user can't change their mind on the same tap). For multi-
  /// select we debounce by [_multiDebounce] so rapid toggles are coalesced
  /// into one request instead of one per tap.
  ///
  /// The push is fire-and-forget: failures are silently swallowed because the
  /// full answer set is re-pushed at submit time anyway. This is purely an
  /// optimistic reliability layer.
  static const Duration _multiDebounce = Duration(milliseconds: 800);

  void _schedulePush(String stateKey, {bool immediate = false}) {
    _pushDebounceTimers[stateKey]?.cancel();
    if (immediate) {
      _pushAnswerNow(stateKey);
    } else {
      _pushDebounceTimers[stateKey] =
          Timer(_multiDebounce, () => _pushAnswerNow(stateKey));
    }
  }

  /// Finds the real question ID and attempt ID for [stateKey], builds the
  /// answer payload, and fires a single upsertAnswer call in the background.
  void _pushAnswerNow(String stateKey) {
    _pushDebounceTimers.remove(stateKey);
    final a = attempt;
    if (a == null) return;

    // Locate the question that owns this stateKey by checking each position.
    // This is O(n) but n is small (quiz length) and this runs off the hot path.
    for (int pos = 0; pos < a.questions.length; pos++) {
      final q = a.questions[pos];
      if (_stableKeyForPosition(pos, q.id) != stateKey) continue;

      final choiceIds = selectedChoices[stateKey] ?? [];
      final code = codeAnswers[stateKey] ?? '';
      if (choiceIds.isEmpty && code.isEmpty) return; // nothing to push

      final payload = Answer(
        questionId: q.id,
        selectedChoiceIds: choiceIds,
        codeText: code,
        marksAwarded: 0,
      ).toJson();

      // Push and track success — mark this key as synced so _pushToServer
      // can skip it and go straight to submit(), saving a full round-trip.
      AttemptService.instance
          .upsertAnswer(a.id, payload)
          .then((_) => _pushedStateKeys.add(stateKey))
          .catchError((_) {
        // Failed — leave key out of _pushedStateKeys so submit re-tries it.
        return false;
      });
      return;
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  /// Builds the list of [Answer] objects from whatever the user selected/typed.
  ///
  /// Returns one [Answer] per question, in the same positional order as
  /// [attempt.questions].  Unanswered questions get an empty Answer so that
  /// [_computeLocalResult] can match by index instead of by questionId —
  /// avoiding map-key collisions when the server reuses the same questionId
  /// across multiple questions.
  List<Answer> _buildAnswers() {
    if (attempt == null) return [];
    final questions = attempt!.questions;
    return List.generate(questions.length, (pos) {
      final q = questions[pos];
      final key = _stableKeyForPosition(pos, q.id);
      final choiceIds = selectedChoices[key] ?? [];
      final code = codeAnswers[key] ?? '';
      return Answer(
        questionId: q.id,
        selectedChoiceIds: choiceIds,
        codeText: code,
        marksAwarded: 0, // server fills this in
      );
    });
  }

  /// Mirrors `QuestionCard._stableQuestionKey()` — used by `_buildAnswers()`
  /// to look up the in-memory state slot for a question at position [pos].
  /// Falls back to a positional key when the server id is empty/blank.
  static String _stableKeyForPosition(int pos, String id) {
    return id.isNotEmpty ? 'q${pos}_$id' : 'q$pos';
  }

  /// Public version of [_stableKeyForPosition] for use by other widgets /
  /// screens that need to read or write per-question state (e.g. the
  /// bottom-pager chips, the review screen, the coding screen).
  ///
  /// The positional key is the only safe way to address a question in the
  /// in-memory state maps — see `QuestionCard._resolvedId()` for why the
  /// raw `question.id` is not used as a key.
  static String stateKeyFor(Question q, int globalIndex) =>
      _stableKeyForPosition(globalIndex, q.id);

  /// Submits the attempt.
  ///
  /// Flow:
  ///   1. Compute the result locally — purely synchronous, zero network wait.
  ///   2. Atomically store the result, clear the attempt, and flip submitState
  ///      to done — all in a single notifyListeners() call so the UI jumps
  ///      straight to the result screen with no intermediate spinner frame.
  ///   3. Push all answers + submit to the server silently in the background.
  ///      Retries with exponential backoff up to [_maxSubmitRetries] times.
  ///
  /// Returns the locally-computed [QuizResult] immediately (never null unless
  /// there is no active attempt).
  QuizResult? submitAndPush() {
    if (attempt == null) return null;

    _timer?.cancel();

    // Flush any pending per-answer debounce timers so in-flight selections
    // are captured before we snapshot the answer list.
    for (final t in _pushDebounceTimers.values) {
      t.cancel();
    }
    _pushDebounceTimers.clear();

    // Capture time used before clearing state.
    timeUsedSeconds = totalSeconds - remainingSeconds;
    quizTotalSeconds = totalSeconds;
    serverSyncDone = false;
    serverSyncFailed = false;

    final attemptId = attempt!.id;
    final quizId = attempt!.quizId;
    final answers = _buildAnswers();
    final localResult = _computeLocalResult(answers);

    // ── Atomic state transition ───────────────────────────────────────────────
    // Set result BEFORE clearing attempt and before notifyListeners().
    // This guarantees the result screen sees a non-null result the very first
    // time it builds — no intermediate "Loading…" frame.
    result = localResult;
    attempt = null;
    submitState = SubmitState.done;
    notifyListeners(); // single notify — result screen renders immediately

    // Save the attempt ID locally so reconcileStaleAttempts can clean up.
    AttemptStore.instance.save(quizId, attemptId);

    // Push to server silently in background.
    _pushToServer(attemptId, answers);

    return localResult;
  }

  /// Computes a [QuizResult] entirely from local data.
  ///
  /// For MCQ questions, correctness is determined locally by comparing the
  /// user's selected choice IDs against [Choice.isCorrect] on the question
  /// model. Rules:
  ///   - mcq_single / code_mcq : correct iff the one chosen choice is marked
  ///     correct.
  ///   - mcq_multi             : correct iff the selected set exactly equals
  ///     the set of all correct choices (no extras, none missing).
  ///   - coding                : always left as pending (isCorrect = null,
  ///     marksAwarded = 0) — graded manually by the admin.
  ///
  /// If the server withheld [Choice.isCorrect] for every choice on a question
  /// (all are null), that question is also left as pending so the result
  /// screen can show "Pending" instead of a misleading wrong/correct badge.
  ///
  /// [score] is the sum of marks awarded across all locally-graded questions.
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

    // Iterate by position so that questions sharing the same server ID don't
    // collide in a map — each answer at index [i] corresponds to the question
    // at the same index in attempt.questions.
    double totalScore = 0;

    final answerResults = List.generate(attempt!.questions.length, (i) {
      final q = attempt!.questions[i];
      // answers list is now always the same length as questions (one-per-position).
      final submitted = i < answers.length
          ? answers[i]
          : Answer(
              questionId: q.id,
              selectedChoiceIds: [],
              codeText: '',
              marksAwarded: 0,
            );

      // Coding questions are graded by the admin — leave pending.
      if (q.qtype == QuestionType.coding) {
        return AnswerResult(question: q, answer: submitted);
      }

      // Check whether the server provided correctness data at all.
      // If every choice has isCorrect == null the server withheld the
      // answer key — fall back to pending.
      final hasCorrectnessData = q.choices.any((c) => c.isCorrect != null);
      if (!hasCorrectnessData) {
        return AnswerResult(question: q, answer: submitted);
      }

      // Derive the correct-choice set from the local question model.
      final correctIds =
          q.choices.where((c) => c.isCorrect == true).map((c) => c.id).toSet();
      final selectedSet = submitted.selectedChoiceIds.toSet();

      bool isCorrect;
      if (selectedSet.isEmpty) {
        // Unanswered — not correct.
        isCorrect = false;
      } else if (q.qtype == QuestionType.mcqMulti) {
        // Multi-select: must match exactly — no extras, no missing.
        isCorrect = selectedSet.length == correctIds.length &&
            selectedSet.every((id) => correctIds.contains(id));
      } else {
        // Single-select (mcqSingle, codeMcq): the one chosen choice must be correct.
        isCorrect = selectedSet.length == 1 &&
            correctIds.contains(selectedSet.first);
      }

      final marks = isCorrect ? q.marks : 0.0;
      totalScore += marks;

      final gradedAnswer = Answer(
        questionId: submitted.questionId,
        selectedChoiceIds: submitted.selectedChoiceIds,
        codeText: submitted.codeText,
        isCorrect: isCorrect,
        marksAwarded: marks,
      );

      return AnswerResult(question: q, answer: gradedAnswer);
    }).toList();

    return QuizResult(
      id: '',
      quizId: attempt!.quizId,
      status: 'submitted',
      totalMarks: attempt!.totalMarks,
      score: totalScore,
      answers: answerResults,
    );
  }

  /// Pushes all answers in parallel, then fires the submit endpoint.
  /// On success, replaces the locally-computed pending result with the
  /// server-graded result so the result screen shows real scores.
  /// Retries on transient failures with exponential backoff.
  Future<void> _pushToServer(String attemptId, List<Answer> answers) async {
    try {
      // Only re-upsert answers that weren't successfully pushed on selection.
      // Answers already in _pushedStateKeys were sent immediately when the
      // user tapped — no need to send them again, saving N round-trips before
      // the submit call and making the result screen appear faster.
      final attempt = this.attempt; // may already be null (cleared above)
      final notYetPushed = answers.where((a) {
        if (a.selectedChoiceIds.isEmpty && a.codeText.isEmpty) return false;
        // Find the stateKey for this answer's question.
        if (attempt != null) {
          for (int pos = 0; pos < attempt.questions.length; pos++) {
            if (attempt.questions[pos].id == a.questionId) {
              final key = _stableKeyForPosition(pos, a.questionId);
              return !_pushedStateKeys.contains(key);
            }
          }
        }
        // If we can't match, re-push to be safe.
        return true;
      }).toList();

      if (notYetPushed.isNotEmpty) {
        await Future.wait(
          notYetPushed.map(
            (answer) => AttemptService.instance.upsertAnswer(
              attemptId,
              answer.toJson(),
            ),
          ),
          eagerError: false,
        );
      }

      final serverResult = await AttemptService.instance.submit(attemptId);
      _cancelSubmitRetry();
      serverSyncDone = true;

      // Replace the pending local result with the server-graded result.
      // If the server returned a populated answers list, use it as-is —
      // it has real is_correct and marks_awarded values.
      // If the server returned an empty answers list (some APIs only return
      // the aggregate score without per-answer detail), merge the server
      // score onto our locally-built result which already has all question
      // objects, and patch each answer's isCorrect/marksAwarded from the
      // server's per-answer data if available.
      if (result != null) {
        final serverAnswers = serverResult.answers;
        final List<AnswerResult> mergedAnswers;

        if (serverAnswers.isNotEmpty &&
            serverAnswers.first.question.id.isNotEmpty) {
          // Server returned full answer+question objects.
          // Prefer our local question objects (which carry the shuffled
          // choice order the user actually saw) over the server's copies.
          // Only take grades (isCorrect, marksAwarded) and selectedChoiceIds
          // from the server.
          final localQuestionMap = {
            for (final ar in result!.answers) ar.question.id: ar.question
          };
          final localAnswerMap = {
            for (final ar in result!.answers) ar.answer.questionId: ar.answer
          };
          mergedAnswers = serverAnswers.map((sa) {
            final localQ = localQuestionMap[sa.question.id];
            final localA = localAnswerMap[sa.answer.questionId];
            return AnswerResult(
              // Keep local question so shuffled choice order is preserved.
              question: localQ ?? sa.question,
              answer: Answer(
                questionId: sa.answer.questionId,
                // Prefer local selectedChoiceIds — the server may not echo
                // them back, but we always have them locally.
                selectedChoiceIds: (sa.answer.selectedChoiceIds.isNotEmpty
                    ? sa.answer.selectedChoiceIds
                    : localA?.selectedChoiceIds) ?? [],
                codeText: sa.answer.codeText.isNotEmpty
                    ? sa.answer.codeText
                    : (localA?.codeText ?? ''),
                isCorrect: sa.answer.isCorrect,
                marksAwarded: sa.answer.marksAwarded,
              ),
            );
          }).toList();
        } else if (serverAnswers.isNotEmpty) {
          // Server returned answer grades but no embedded question detail.
          // Patch our local answers (which have question objects) with the
          // server-graded marks.
          final serverMap = {
            for (final sa in serverAnswers) sa.answer.questionId: sa.answer
          };
          mergedAnswers = result!.answers.map((local) {
            final serverAnswer = serverMap[local.answer.questionId];
            if (serverAnswer == null) return local;
            return AnswerResult(
              question: local.question,
              answer: Answer(
                questionId: local.answer.questionId,
                selectedChoiceIds: local.answer.selectedChoiceIds,
                codeText: local.answer.codeText,
                isCorrect: serverAnswer.isCorrect,
                marksAwarded: serverAnswer.marksAwarded,
              ),
            );
          }).toList();
        } else {
          // Server returned no answers at all — keep local answers but
          // update the aggregate score from the server.
          mergedAnswers = result!.answers;
        }

        result = QuizResult(
          id: serverResult.id,
          quizId: serverResult.quizId,
          status: serverResult.status,
          totalMarks: serverResult.totalMarks > 0
              ? serverResult.totalMarks
              : result!.totalMarks,
          score: serverResult.score,
          submittedAt: serverResult.submittedAt,
          answers: mergedAnswers,
        );
      } else {
        result = serverResult;
      }
      notifyListeners();
    } catch (_) {
      // Transient failure — retry with backoff so the server eventually
      // receives the submit even if the user closes the app.
      if (_submitRetryCount >= _maxSubmitRetries) {
        serverSyncFailed = true;
        notifyListeners();
      } else {
        _scheduleSubmitRetry(attemptId, answers);
      }
    }
  }

  /// Auto-submit triggered by the countdown timer or proctoring violations.
  /// Uses the same submitAndPush() path so the logic is consistent.
  /// [onDone] is called synchronously after the result is computed so the
  /// caller (QuizScreen) can navigate immediately without relying on a
  /// postFrameCallback that may be missed during rapid state transitions.
  void autoSubmit({VoidCallback? onDone}) {
    submitAndPush();
    onDone?.call();
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
    _onAutoSubmitNavigate = null;
    for (final t in _pushDebounceTimers.values) {
      t.cancel();
    }
    _pushDebounceTimers.clear();
    attempt = null;
    result = null;
    submitState = SubmitState.idle;
    selectedChoices.clear();
    codeAnswers.clear();
    currentQuestionIndex = 0;
    timeUsedSeconds = 0;
    quizTotalSeconds = 0;
    serverSyncDone = false;
    serverSyncFailed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelSubmitRetry();
    for (final t in _pushDebounceTimers.values) {
      t.cancel();
    }
    _pushDebounceTimers.clear();
    super.dispose();
  }
}
