import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import '../widgets/question_card.dart';
import '../widgets/timer_bar.dart';
import '../widgets/bwb_button.dart';
import '../services/lockdown_service.dart';
import '../widgets/lockdown_overlay.dart';
import '../models/question.dart';
import 'topic_index.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late PageController _pageController;
  bool _showingViolationDialog = false;

  // Topic tab state
  late TabController _tabController;
  List<_TopicGroup> _topics = [];
  int _activeTopicIndex = 0;

  // Scroll controller for the bottom question-chip row
  final ScrollController _pagerScrollController = ScrollController();
  int _lastScrolledIndex = -1;

  // Keys for measuring the Prev/Next topic buttons so the auto-scroll
  // math doesn't have to rely on hard-coded pixel widths.
  final GlobalKey _prevButtonKey = GlobalKey();
  final GlobalKey _nextButtonKey = GlobalKey();
  double _prevButtonWidth = 0;
  double _nextButtonWidth = 0;
  static const double _chipWidth = 36;
  static const double _chipHorizontalMargin = 4; // each side
  static const double _chipRowGap = 8; // gap between prev button and first chip

  // ── Question auto-advance tokens ─────────────────────────────────────────────
  //
  // When a single-choice option is tapped, we schedule a 400ms-delayed
  // animateToPage to the next question.  We track the most-recently-scheduled
  // advance per page so that:
  //
  //   1. A user who rapidly taps a choice and then swipes away doesn't get
  //      force-pulled back to the auto-advance target.
  //   2. A user who taps, then taps a DIFFERENT option on the same page
  //      doesn't fire two animateToPage() calls racing each other
  //      (last tap wins).
  //   3. A state rebuild that recreates the QuestionCard doesn't cause the
  //      captured `i` in the closure to drift onto the wrong page.
  int _latestAutoAdvanceToken = 0;
  final Map<int, int> _pageAutoAdvanceToken = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 0, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildTopicGroups();
      LockdownService.instance.enableLockdown(onViolation: _handleViolation);

      // Register the timer-expiry navigation callback so when the countdown
      // hits zero, autoSubmit fires and then immediately navigates here —
      // without relying on a postFrameCallback that can be missed.
      //
      // NOTE: this must NOT call setAttempt() again — setAttempt() resets
      // violationCount, clears every selected answer, and restarts the
      // timer/push state. It previously did, which meant any state built
      // up before this callback ran (rare, but possible on a slow first
      // frame) was silently wiped right as the quiz screen mounted.
      if (mounted) {
        context.read<AttemptState>().setTimerExpiredCallback(_navigateToResult);
      }
    });
  }

  void _navigateToResult() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/result', (r) => r.isFirst);
  }

  void _buildTopicGroups() {
    final attemptState = context.read<AttemptState>();
    final questions = attemptState.attempt?.questions ?? [];

    // Group questions by topic, preserving original order
    final Map<String, _TopicGroup> topicMap = {};
    final List<String> topicOrder = [];
    for (final q in questions) {
      final tid = q.topicId.isNotEmpty ? q.topicId : '__default__';
      final tname = q.topicName.isNotEmpty ? q.topicName : 'Questions';
      if (!topicMap.containsKey(tid)) {
        topicMap[tid] = _TopicGroup(id: tid, name: tname, questions: []);
        topicOrder.add(tid);
      }
      topicMap[tid]!.questions.add(q);
    }

    final newTopics = topicOrder.map((id) => topicMap[id]!).toList();

    if (!mounted) return;

    // Rebuild TabController if topic count changed
    _tabController.dispose();
    _tabController = TabController(length: newTopics.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      _switchToTopic(_tabController.index);
    });

    setState(() {
      _topics = newTopics;
      _activeTopicIndex = 0;
    });
  }

  void _switchToTopic(int topicIndex) {
    _goToTopic(topicIndex);
  }

  /// Single entry point for switching to a topic by index.
  /// Used by the Prev/Next buttons, the bottom-sheet topic selector, and
  /// the review screen's "jump to question" callback.
  void _goToTopic(int topicIndex) {
    if (topicIndex < 0 || topicIndex >= _topics.length) return;
    if (!mounted) return;

    setState(() => _activeTopicIndex = topicIndex);

    // Reset the pager scroll guard so the new topic's first chip is
    // scrolled into view even if the global index didn't change.
    _lastScrolledIndex = -1;

    if (_tabController.length > topicIndex &&
        _tabController.index != topicIndex) {
      _tabController.animateTo(topicIndex);
    }

    // Jump (not animate) to the first question of the new topic so the
    // tap feels immediate and never races with the page controller.
    final globalIndex = _globalIndexForTopicStart(topicIndex);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(globalIndex);
    }

    final attemptState = context.read<AttemptState>();
    attemptState.goToQuestion(globalIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollPagerToIndex(globalIndex);
    });
  }

  /// The global index (across all questions) of the first question in [topicIndex]
  int _globalIndexForTopicStart(int topicIndex) =>
      globalIndexForTopicStart(_topicCounts, topicIndex);

  /// Which topic does global question index [globalIndex] belong to?
  int _topicIndexForGlobal(int globalIndex) =>
      topicIndexForGlobal(_topicCounts, globalIndex);

  /// Cached per-topic question counts — used by the helpers above and the
  /// pager auto-scroll math. Recomputed inside build, never mutated.
  List<int> get _topicCounts =>
      _topics.map((t) => t.questions.length).toList(growable: false);

  /// Flat ordered list of all questions in topic-group order.
  /// This is the single source of truth for both the PageView and all
  /// global-index calculations. Using attempt.questions directly would
  /// break if the server returns questions interleaved across topics
  /// (e.g. [Q_A, Q_B, Q_A]) — the PageView page-index would then differ
  /// from the topic-offset-based globalIndex used by the pager chips,
  /// review screen, and stateKeyFor(), causing wrong keys and missed answers.
  List<Question> get _orderedQuestions =>
      [for (final t in _topics) ...t.questions];


  @override
  void dispose() {
    LockdownService.instance.disableLockdown();
    WidgetsBinding.instance.removeObserver(this);
    context.read<AttemptState>().clearAutoSubmitCallback();
    _pageController.dispose();
    _tabController.dispose();
    _pagerScrollController.dispose();
    _pageAutoAdvanceToken.clear();
    super.dispose();
  }

  void _handleViolation(String reason) {
    if (!mounted) return;
    final attemptState = context.read<AttemptState>();
    attemptState.recordViolation(reason);

    if (!_showingViolationDialog) {
      _showingViolationDialog = true;
      LockdownService.instance.notifyDialogOpen();
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (navCtx, _, _) => LockdownOverlayDialog(
            reason: reason,
            onDismiss: () {
              _showingViolationDialog = false;
              LockdownService.instance.notifyDialogClosed();
              Navigator.of(navCtx, rootNavigator: true).pop();
              // Read isFinal fresh — a 3rd violation may have fired while
              // this dialog was already open (isFinal was false at open time).
              final nowFinal = context.read<AttemptState>().violationCount
                  >= AttemptState.maxViolations;
              if (nowFinal) {
                _navigateToResult();
              } else {
                LockdownService.instance
                    .enableLockdown(onViolation: _handleViolation);
              }
            },
          ),
        ),
      ).then((_) => _showingViolationDialog = false);
    }
    // If dialog is already open, recordViolation() already updated
    // AttemptState.violationCount — the overlay rebuilds via context.watch
    // and shows the new count + triggers auto-submit on the 3rd violation.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LockdownService.instance.handleLifecycleState(state);
    if (state == AppLifecycleState.resumed) _checkExpired();
  }

  Future<void> _checkExpired() async {
    final attemptState = context.read<AttemptState>();
    if (attemptState.attempt == null) return;
    if (DateTime.now().toUtc().isAfter(attemptState.attempt!.deadlineDateTime)) {
      attemptState.autoSubmit();
      if (mounted) _navigateToResult();
    }
  }

  Future<bool> _onWillPop() async {
    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(
    //     content: Text('Quiz is in progress! You cannot leave until submitted.'),
    //     duration: Duration(seconds: 2),
    //   ),
    // );
    return false;
  }

  bool _isReviewingOrSubmitting = false;

  Future<void> _submit({bool isTimeExpired = false}) async {
    if (_isReviewingOrSubmitting) return;
    _isReviewingOrSubmitting = true;

    final confirm = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizReviewScreen(
          topics: _topics,
          isTimeExpired: isTimeExpired,
          onSelectQuestion: (globalIdx, reviewContext) {
            // Pop the review screen first, then jump to question
            Navigator.pop(reviewContext, false);
            final newTopicIdx = _topicIndexForGlobal(globalIdx);
            _goToTopic(newTopicIdx);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(globalIdx);
            }
          },
        ),
      ),
    );

    _isReviewingOrSubmitting = false;
    if (confirm != true) return;
    if (!mounted) return;

    final attemptState = context.read<AttemptState>();

    // submitAndPush() is fully synchronous from the UI perspective:
    // it computes the local result, stores it in state, clears the attempt,
    // and fires a single notifyListeners() — all before returning.
    attemptState.submitAndPush();

    if (!mounted) return;
    // Remove the quiz screen from the stack so back-button can't return to it.
    Navigator.of(context).pushNamedAndRemoveUntil('/result', (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final attemptState = context.watch<AttemptState>();
    final attempt = attemptState.attempt;

    if (attempt != null && attemptState.remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _submit(isTimeExpired: true);
        }
      });
    }

    // Timer expired and autoSubmit() already ran (attempt cleared, result set).
    // Navigate to result screen now — the spinner below never navigates itself.
    //
    // Guarded with !_showingViolationDialog: a 3rd security violation also
    // clears attempt/sets submitState=done via recordViolation()->autoSubmit(),
    // but synchronously, before the user has seen the "QUIZ AUTO-SUBMITTED"
    // dialog. Without this guard, this postFrameCallback could yank the whole
    // route (dialog included) to /result on the very next frame — the dialog's
    // own onDismiss already handles navigation for that case once the user
    // taps "View Result", so this fallback should stand down while it's open.
    if (attempt == null &&
        attemptState.submitState == SubmitState.done &&
        !_showingViolationDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/result', (r) => r.isFirst);
        }
      });
    }

    if (attempt == null) {
      // If a result is already computed (post-submit), the _submit() handler
      // navigates to /result synchronously. Nothing to show here.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final questions = _orderedQuestions;
    final totalSeconds = attemptState.totalSeconds;
    final hasMultipleTopics = _topics.length > 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final pop = await _onWillPop();
        if (pop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: hasMultipleTopics
              ? Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.auto_awesome_mosaic_outlined, color: Colors.black87, size: 35),
                      onPressed: _showTopicSelectorPopUp,
                    ),
                    Expanded(
                      child: Text(
                        _topics[_activeTopicIndex].name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(Icons.article_outlined, color: Colors.black87),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _topics.isNotEmpty ? _topics.first.name : 'Quiz',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: BwbButton(
                label: 'Submit',
                onPressed: attemptState.isSubmitBlocked ? null : _submit,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            TimerBar(totalSeconds: totalSeconds),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: questions.length,
                onPageChanged: (globalIndex) {
                  attemptState.goToQuestion(globalIndex);
                  final newTopicIdx = _topicIndexForGlobal(globalIndex);
                  if (newTopicIdx != _activeTopicIndex) {
                    setState(() => _activeTopicIndex = newTopicIdx);
                    if (_tabController.index != newTopicIdx) {
                      _tabController.animateTo(newTopicIdx);
                    }
                  }
                  // The user swiped away from any page that had a pending
                  // auto-advance scheduled — clear its token so a later
                  // tap on that page (after a swipe round-trip) can fire
                  // a fresh advance without being suppressed by the stale
                  // token.
                  _pageAutoAdvanceToken.remove(globalIndex);
                  // Auto-scroll the bottom chip row to keep current question visible
                  _scrollPagerToIndex(globalIndex);
                },
                itemBuilder: (context, i) {
                  final localIdx = i - _globalIndexForTopicStart(_topicIndexForGlobal(i));
                  final question = questions[i];
                  // ValueKey on the global position index — never on question.id.
                  // question.id can be '' or a short integer like "1" that
                  // collides across questions when the server reuses IDs.
                  // A position-based key guarantees Flutter never recycles
                  // a page's element tree onto a different question.
                  return SingleChildScrollView(
                    key: ValueKey(i),
                    child: QuestionCard(
                      question: question,
                      index: localIdx,
                      globalIndex: i,
                      onSingleChoiceSelected: () {
                        // Auto-slide to the next question after a short
                        // delay.  Guard rails:
                        //   1. Only advance if the user is still on the
                        //      same page (they may have swiped away).
                        //   2. A token-per-page map cancels a previously-
                        //      scheduled advance when the same page is
                        //      tapped again — prevents two animateToPage
                        //      calls racing each other.
                        //   3. Bail on the last page.
                        final tappedPage = i;
                        final nextPage = tappedPage + 1;
                        if (nextPage >= questions.length) return;
                        final myToken = ++_latestAutoAdvanceToken;
                        _pageAutoAdvanceToken[tappedPage] = myToken;
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (!mounted) return;
                          // If the user re-tapped (different option on
                          // the same page) we want the *latest* token to
                          // be the one that fires — older ones become
                          // no-ops.
                          if (_pageAutoAdvanceToken[tappedPage] != myToken) {
                            return;
                          }
                          final currentPage =
                              _pageController.page?.round() ?? tappedPage;
                          if (currentPage != tappedPage) return;
                          _pageController.animateToPage(
                            nextPage,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            // Bottom pager — shows only current topic's questions
            _buildPager(attemptState),
          ],
        ),
      ),
    );
  }

  // Auto-scroll the bottom chips row so the current question is always visible
  void _scrollPagerToIndex(int globalIndex) {
    if (!_pagerScrollController.hasClients) return;
    if (_lastScrolledIndex == globalIndex) return;
    _lastScrolledIndex = globalIndex;

    // Measure the Prev/Next topic buttons if we haven't yet. The keys let us
    // read their actual width after the first layout, instead of guessing.
    _prevButtonWidth = _prevButtonKey.currentContext?.size?.width ?? 0;
    _nextButtonWidth = _nextButtonKey.currentContext?.size?.width ?? 0;

    final fullChipWidth = _chipWidth + (_chipHorizontalMargin * 2);
    final topicOffset = _globalIndexForTopicStart(_activeTopicIndex);
    final localIndex = globalIndex - topicOffset;

    // Where the chip sits inside the scroll viewport's content space.
    final chipCenterX = _prevButtonWidth +
        (localIndex * fullChipWidth) +
        (fullChipWidth / 2);

    // Aim to put the chip in the middle of the visible area, biased so
    // the Next button on the right doesn't push the chip off-screen.
    final viewportWidth = _pagerScrollController.position.viewportDimension;
    final visibleRightOffset = _nextButtonWidth;
    final halfVisible = (viewportWidth - visibleRightOffset) / 2;

    final desired = chipCenterX - halfVisible;
    final maxScroll = _pagerScrollController.position.maxScrollExtent;
    _pagerScrollController.animateTo(
      desired.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildPager(AttemptState state) {
    if (_topics.isEmpty) return const SizedBox.shrink();

    final currentTopic = _topics[_activeTopicIndex];
    final topicQuestions = currentTopic.questions;
    final globalOffset = _globalIndexForTopicStart(_activeTopicIndex);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question number chips (for this topic only)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _pagerScrollController,
            child: Row(
              children: [
                if (_activeTopicIndex > 0)
                  Padding(
                    key: _prevButtonKey,
                    padding: const EdgeInsets.only(right: _chipRowGap),
                    child: InkWell(
                      onTap: () => _goToTopic(_activeTopicIndex - 1),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BwbTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('← Prev', style: TextStyle(color: BwbTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ),
                ...List.generate(topicQuestions.length, (localI) {
                final globalI = globalOffset + localI;
                final question = topicQuestions[localI];
                // Use the positional stable key for state lookups — the raw
                // question.id may collide across questions (the server
                // re-uses short integer ids per quiz/topic), so reading by
                // it would make the wrong chip appear "answered" / "flagged".
                final stateKey = AttemptState.stateKeyFor(question, globalI);
                final hasAnswer =
                    (state.selectedChoices[stateKey]?.isNotEmpty ?? false) ||
                    (state.codeAnswers[stateKey]?.isNotEmpty ?? false);
                final isCurrent = globalI == state.currentQuestionIndex;
                final isFlagged = state.flaggedQuestions.contains(stateKey);

                Color bgColor;
                if (isCurrent) {
                  bgColor = Colors.black;
                } else if (hasAnswer) {
                  bgColor = const Color(0xFFDCFCE7);
                } else {
                  bgColor = Colors.white;
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_pageController.hasClients) {
                        _pageController.animateToPage(
                          globalI,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: _chipHorizontalMargin),
                          width: _chipWidth,
                          height: 36,
                          decoration: BoxDecoration(
                            color: bgColor,
                            border: Border.all(
                              color: isFlagged
                                  ? Colors.orange
                                  : (hasAnswer
                                      ? const Color(0xFF16A34A)
                                      : Colors.black45),
                              width: isCurrent ? 2.5 : (isFlagged ? 2 : 1),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${localI + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isCurrent
                                    ? Colors.white
                                    : (hasAnswer
                                        ? const Color(0xFF15803D)
                                        : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                        if (isFlagged)
                          const Positioned(
                            top: -4,
                            right: 0,
                            child: Icon(Icons.flag, size: 12, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              if (_activeTopicIndex < _topics.length - 1)
                Padding(
                  key: _nextButtonKey,
                  padding: const EdgeInsets.only(left: _chipRowGap),
                  child: InkWell(
                    onTap: () => _goToTopic(_activeTopicIndex + 1),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: BwbTheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Next →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  void _showTopicSelectorPopUp() {
    // Capture the State so the bottom-sheet's onTap can act on it
    // after Navigator.pop without depending on the sheet's BuildContext.
    final outerState = this;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text('Select Topic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: BwbTheme.primary)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: outerState._topics.length,
                  itemBuilder: (ctx, i) {
                    final t = outerState._topics[i];
                    final isSelected = i == outerState._activeTopicIndex;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      title: Text(t.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 15)),
                      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        // Read from the outer state to avoid a stale
                        // BuildContext after the bottom sheet dismisses.
                        if (i != outerState._activeTopicIndex) {
                          outerState._goToTopic(i);
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

// ─── Data model for topic grouping ────────────────────────────────────────────
class _TopicGroup {
  final String id;
  final String name;
  final List<Question> questions;
  _TopicGroup({required this.id, required this.name, required this.questions});
}

// ─── Quiz Review Screen ───────────────────────────────────────────────────────
class _QuizReviewScreen extends StatefulWidget {
  final List<_TopicGroup> topics;
  final Function(int, BuildContext) onSelectQuestion;
  final bool isTimeExpired;

  const _QuizReviewScreen({
    required this.topics,
    required this.onSelectQuestion,
    this.isTimeExpired = false,
  });

  @override
  State<_QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<_QuizReviewScreen> {
  bool _isSubmitting = false;
  final Set<String> _flushedStateKeys = {};
  int _totalQuestionsToFlush = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isTimeExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startParallelFlushAndSubmit();
      });
    }
  }

  Future<void> _startParallelFlushAndSubmit() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    final attemptState = context.read<AttemptState>();
    final attempt = attemptState.attempt;

    if (attempt != null) {
      _totalQuestionsToFlush = attempt.questions.length;
      await attemptState.flushAllAnswersInParallel(
        onQuestionFlushed: (stateKey, success) {
          if (mounted) {
            setState(() {
              _flushedStateKeys.add(stateKey);
            });
          }
        },
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final totalSeconds = state.totalSeconds;

    // Compute totals eagerly so the bottom summary bar is accurate
    int totalQs = 0;
    int totalAns = 0;
    int runningGlobal = 0;
    for (final topic in widget.topics) {
      for (final q in topic.questions) {
        totalQs++;
        final stateKey = AttemptState.stateKeyFor(q, runningGlobal);
        if ((state.selectedChoices[stateKey]?.isNotEmpty ?? false) ||
            (state.codeAnswers[stateKey]?.isNotEmpty ?? false)) {
          totalAns++;
        }
        runningGlobal++;
      }
    }

    final flushedCount = _flushedStateKeys.length;
    final flushProgress =
        _totalQuestionsToFlush > 0 ? (flushedCount / _totalQuestionsToFlush) : 0.0;

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review Assessment',
              style: TextStyle(fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          ),
        ),
        body: Column(
          children: [
            TimerBar(totalSeconds: totalSeconds),
            if (widget.isTimeExpired)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: const Color(0xFFFEF3C7),
                child: Row(
                  children: const [
                    Icon(Icons.timer_off_rounded, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Time Expired! Auto-submitting assessment...',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isSubmitting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: const Color(0xFFECFDF5),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF059669),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Flushing answers to server in parallel...',
                              style: TextStyle(
                                color: Color(0xFF065F46),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$flushedCount / $totalQs Checked',
                          style: const TextStyle(
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: flushProgress,
                        backgroundColor: const Color(0xFFA7F3D0),
                        color: const Color(0xFF059669),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: BwbTheme.primary.withValues(alpha: 0.05),
                child: const Text(
                  'Tap any question box below to jump directly to it.',
                  style: TextStyle(
                      color: BwbTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.topics.length,
                itemBuilder: (ctx, i) {
                  final topic = widget.topics[i];
                  int topicAns = 0;
                  final boxes = <Widget>[];
                  for (int qi = 0; qi < topic.questions.length; qi++) {
                    final q = topic.questions[qi];
                    int globalIdx = 0;
                    for (int t = 0; t < i; t++) {
                      globalIdx += widget.topics[t].questions.length;
                    }
                    globalIdx += qi;

                    final stateKey = AttemptState.stateKeyFor(q, globalIdx);
                    final hasAns =
                        (state.selectedChoices[stateKey]?.isNotEmpty ?? false) ||
                        (state.codeAnswers[stateKey]?.isNotEmpty ?? false);
                    if (hasAns) {
                      topicAns++;
                    }
                    final isFlagged = state.flaggedQuestions.contains(stateKey);
                    final isFlushed = _flushedStateKeys.contains(stateKey);

                    Color boxBgColor;
                    Color borderColor;
                    Widget childWidget;

                    if (_isSubmitting) {
                      if (isFlushed) {
                        boxBgColor = const Color(0xFF059669);
                        borderColor = const Color(0xFF047857);
                        childWidget = const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 22,
                        );
                      } else if (hasAns) {
                        boxBgColor = const Color(0xFFD1FAE5);
                        borderColor = const Color(0xFF10B981);
                        childWidget = const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF059669),
                          ),
                        );
                      } else {
                        boxBgColor = Colors.grey.shade100;
                        borderColor = Colors.grey.shade300;
                        childWidget = Text(
                          '${qi + 1}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        );
                      }
                    } else {
                      if (hasAns) {
                        boxBgColor = const Color(0xFF10B981);
                        borderColor = const Color(0xFF059669);
                        childWidget = Text(
                          '${qi + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        );
                      } else {
                        boxBgColor = Colors.white;
                        borderColor = Colors.grey.shade400;
                        childWidget = Text(
                          '${qi + 1}',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        );
                      }
                    }

                    boxes.add(
                      GestureDetector(
                        onTap: _isSubmitting
                            ? null
                            : () => widget.onSelectQuestion(globalIdx, context),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: boxBgColor,
                                border: Border.all(color: borderColor, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: childWidget),
                            ),
                            if (isFlagged && !_isSubmitting)
                              const Positioned(
                                top: -4,
                                right: -4,
                                child: Icon(Icons.flag_rounded,
                                    size: 16, color: Colors.orange),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              topic.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Text(
                            '$topicAns / ${topic.questions.length} Answered',
                            style: TextStyle(
                              color: topicAns == topic.questions.length
                                  ? const Color(0xFF10B981)
                                  : Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 6,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: boxes,
                      ),
                      const SizedBox(height: 24),
                      if (i < widget.topics.length - 1) const Divider(),
                      if (i < widget.topics.length - 1) const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.black12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  )
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Final Submission',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('$totalAns Answered',
                              style: const TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          if (totalQs - totalAns > 0)
                            Text('${totalQs - totalAns} Unanswered',
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitting ? Colors.grey.shade400 : Colors.black,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSubmitting ? null : _startParallelFlushAndSubmit,
                      child: _isSubmitting
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Pushed to Server...',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            )
                          : const Text(
                              'Submit Quiz',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
