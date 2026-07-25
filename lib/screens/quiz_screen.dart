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
  bool _submitting = false;
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 0, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildTopicGroups();
      LockdownService.instance.enableLockdown(onViolation: _handleViolation);
    });
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


  @override
  void dispose() {
    LockdownService.instance.disableLockdown();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _tabController.dispose();
    _pagerScrollController.dispose();
    super.dispose();
  }

  void _handleViolation(String reason) {
    if (!mounted) return;
    final attemptState = context.read<AttemptState>();
    attemptState.recordViolation(reason);

    if (!_showingViolationDialog) {
      _showingViolationDialog = true;
      // Push a transparent full-screen route so the overlay covers the
      // entire viewport (including the system bars) instead of being
      // constrained to the centered Dialog insets.
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (navCtx, _, _) => ChangeNotifierProvider<AttemptState>.value(
            value: attemptState,
            child: LockdownOverlayDialog(
              reason: reason,
              onDismiss: () {
                _showingViolationDialog = false;
                Navigator.of(navCtx, rootNavigator: true).pop();
                LockdownService.instance.enableLockdown(onViolation: _handleViolation);
              },
            ),
          ),
        ),
      ).then((_) => _showingViolationDialog = false);
    }
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
      await attemptState.autoSubmit();
      if (mounted) Navigator.of(context).pushReplacementNamed('/result');
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

  Future<void> _submit() async {
    final confirm = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizReviewScreen(
          topics: _topics,
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
    if (confirm != true) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    final attemptState = context.read<AttemptState>();
    final result = await attemptState.submit();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) {
      Navigator.of(context).pushReplacementNamed('/result');
    } else {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text(attemptState.errorMessage ?? 'Submit failed')),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    final attemptState = context.watch<AttemptState>();
    final attempt = attemptState.attempt;

    if (attempt != null && attemptState.remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/result', (route) => false);
        }
      });
    }

    if (attempt == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final questions = attempt.questions;
    final deadlineDt = attempt.deadlineDateTime;
    final startedDt = attempt.startedAtDateTime;
    final totalSeconds = deadlineDt.difference(startedDt).inSeconds.abs();
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
                      icon: const Icon(Icons.article_outlined, color: Colors.black87),
                      onPressed: _showTopicSelectorPopUp,
                    ),
                    Expanded(
                      child: Text(
                        _topics[_activeTopicIndex].name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                        maxLines: 2,
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
              child: _submitting
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : BwbButton(
                      label: 'Submit',
                      onPressed: attemptState.isSubmitBlocked ? null : _submit,
                    ),
            ),
          ],
        ),
        body: Column(
          children: [
            TimerBar(totalSeconds: totalSeconds),
            if (attemptState.connectivity == ConnectivityState.offline)
              Container(
                width: double.infinity,
                color: BwbTheme.wrong.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: const Text(
                  'Offline — answers will be saved when reconnected',
                  style: TextStyle(color: BwbTheme.wrong, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
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
                  // Auto-scroll the bottom chip row to keep current question visible
                  _scrollPagerToIndex(globalIndex);
                },
                itemBuilder: (context, i) {
                  final localIdx = i - _globalIndexForTopicStart(_topicIndexForGlobal(i));
                  final question = questions[i];
                  return SingleChildScrollView(
                    child: QuestionCard(
                      question: question,
                      index: localIdx,
                      onSingleChoiceSelected: () {
                        // Auto-slide to next question on single choice selection
                        final nextPage = i + 1;
                        if (nextPage < questions.length) {
                          Future.delayed(const Duration(milliseconds: 350), () {
                            if (mounted) {
                              _pageController.animateToPage(
                                nextPage,
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                              );
                            }
                          });
                        }
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
                final hasAnswer =
                    (state.selectedChoices[question.id]?.isNotEmpty ?? false) ||
                    (state.codeAnswers[question.id]?.isNotEmpty ?? false);
                final isCurrent = globalI == state.currentQuestionIndex;
                final isFlagged = state.flaggedQuestions.contains(question.id);

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

// ─── Topic navigation button ──────────────────────────────────────────────────
// ─── Quiz Review Screen ───────────────────────────────────────────────────────
class _QuizReviewScreen extends StatelessWidget {
  final List<_TopicGroup> topics;
  final Function(int, BuildContext) onSelectQuestion;

  const _QuizReviewScreen({required this.topics, required this.onSelectQuestion});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final attempt = state.attempt;
    final totalSeconds = attempt != null ? attempt.deadlineDateTime.difference(attempt.startedAtDateTime).inSeconds.abs() : 0;
    int totalQs = 0;
    int totalAns = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Assessment', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          TimerBar(totalSeconds: totalSeconds),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: BwbTheme.primary.withValues(alpha: 0.05),
            child: const Text(
              'Tap any question box below to jump directly to it.',
              style: TextStyle(color: BwbTheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: topics.length,
              itemBuilder: (ctx, i) {
                final topic = topics[i];
                int topicAns = 0;
                final boxes = <Widget>[];
                for (int qi = 0; qi < topic.questions.length; qi++) {
                  final q = topic.questions[qi];
                  final hasAns = (state.selectedChoices[q.id]?.isNotEmpty ?? false) ||
                                 (state.codeAnswers[q.id]?.isNotEmpty ?? false);
                  if (hasAns) {
                    topicAns++;
                    totalAns++;
                  }
                  totalQs++;

                  // Calculate global index
                  int globalIdx = 0;
                  for (int t = 0; t < i; t++) {
                    globalIdx += topics[t].questions.length;
                  }
                  globalIdx += qi;
                  final isFlagged = state.flaggedQuestions.contains(q.id);

                  boxes.add(
                    GestureDetector(
                      onTap: () => onSelectQuestion(globalIdx, context),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: hasAns ? const Color(0xFF10B981) : Colors.white,
                              border: Border.all(color: hasAns ? const Color(0xFF059669) : Colors.grey.shade400, width: 1.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${qi + 1}',
                                style: TextStyle(
                                  color: hasAns ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          if (isFlagged)
                            const Positioned(
                              top: -4,
                              right: -4,
                              child: Icon(Icons.flag_rounded, size: 16, color: Colors.orange),
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
                        Expanded(child: Text(topic.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        Text(
                          '$topicAns / ${topic.questions.length} Answered', 
                          style: TextStyle(
                            color: topicAns == topic.questions.length ? const Color(0xFF10B981) : Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          )
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
                    if (i < topics.length - 1) const Divider(),
                    if (i < topics.length - 1) const SizedBox(height: 12),
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
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Final Submission', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('$totalAns Answered', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 13)),
                        if (totalQs - totalAns > 0)
                          Text('${totalQs - totalAns} Unanswered', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit Quiz', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
