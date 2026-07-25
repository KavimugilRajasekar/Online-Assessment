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
    if (topicIndex < 0 || topicIndex >= _topics.length) return;
    setState(() => _activeTopicIndex = topicIndex);

    // Navigate PageController to the first question of the selected topic
    final globalIndex = _globalIndexForTopicStart(topicIndex);
    _pageController.animateToPage(
      globalIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    final attemptState = context.read<AttemptState>();
    attemptState.goToQuestion(globalIndex);
  }

  /// The global index (across all questions) of the first question in [topicIndex]
  int _globalIndexForTopicStart(int topicIndex) {
    int offset = 0;
    for (int i = 0; i < topicIndex; i++) {
      offset += _topics[i].questions.length;
    }
    return offset;
  }

  /// Which topic does global question index [globalIndex] belong to?
  int _topicIndexForGlobal(int globalIndex) {
    int offset = 0;
    for (int i = 0; i < _topics.length; i++) {
      offset += _topics[i].questions.length;
      if (globalIndex < offset) return i;
    }
    return _topics.length - 1;
  }


  @override
  void dispose() {
    LockdownService.instance.disableLockdown();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleViolation(String reason) {
    if (!mounted) return;
    final attemptState = context.read<AttemptState>();
    attemptState.recordViolation(reason);

    if (!_showingViolationDialog) {
      _showingViolationDialog = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ChangeNotifierProvider<AttemptState>.value(
          value: attemptState,
          child: LockdownOverlayDialog(
            reason: reason,
            onDismiss: () {
              _showingViolationDialog = false;
              Navigator.pop(ctx);
              LockdownService.instance.enableLockdown(onViolation: _handleViolation);
            },
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quiz is in progress! You cannot leave until submitted.'),
        duration: Duration(seconds: 2),
      ),
    );
    return false;
  }

  Future<void> _submit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit quiz?'),
        content: const Text('This will end your attempt. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
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
      final msg = attemptState.errorMessage ?? 'Submit failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final attemptState = context.watch<AttemptState>();
    final attempt = attemptState.attempt;

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
          title: const Text('Quiz', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: hasMultipleTopics
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: _buildTopicTabBar(),
                )
              : null,
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
                },
                itemBuilder: (context, i) => SingleChildScrollView(
                  child: QuestionCard(question: questions[i], index: i),
                ),
              ),
            ),
            // Bottom pager — shows only current topic's questions
            _buildPager(attemptState),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicTabBar() {
    if (_topics.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: BwbTheme.primary,
        indicatorWeight: 3,
        labelColor: BwbTheme.primary,
        unselectedLabelColor: Colors.black54,
        labelStyle: const TextStyle(
          fontFamily: BwbTheme.fontFamily,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: BwbTheme.fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: _topics.asMap().entries.map((entry) {
          final i = entry.key;
          final topic = entry.value;
          // Count answered in this topic
          final attemptState = context.read<AttemptState>();
          final answeredCount = topic.questions
              .where((q) =>
                  (attemptState.selectedChoices[q.id]?.isNotEmpty ?? false) ||
                  (attemptState.codeAnswers[q.id]?.isNotEmpty ?? false))
              .length;
          final total = topic.questions.length;
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${i + 1}. ${topic.name}'),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: answeredCount == total
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$answeredCount/$total',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: answeredCount == total
                          ? const Color(0xFF15803D)
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
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
          // Topic label + prev/next topic navigation
          if (_topics.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Row(
                children: [
                  // Prev topic
                  if (_activeTopicIndex > 0)
                    _TopicNavButton(
                      label: '← ${_topics[_activeTopicIndex - 1].name}',
                      onTap: () {
                        _tabController.animateTo(_activeTopicIndex - 1);
                        _switchToTopic(_activeTopicIndex - 1);
                      },
                    ),
                  const Spacer(),
                  // Current topic label
                  Text(
                    currentTopic.name,
                    style: const TextStyle(
                      fontFamily: BwbTheme.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: BwbTheme.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  // Next topic
                  if (_activeTopicIndex < _topics.length - 1)
                    _TopicNavButton(
                      label: '${_topics[_activeTopicIndex + 1].name} →',
                      onTap: () {
                        _tabController.animateTo(_activeTopicIndex + 1);
                        _switchToTopic(_activeTopicIndex + 1);
                      },
                    ),
                ],
              ),
            ),
          // Question number chips (for this topic only)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(topicQuestions.length, (localI) {
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

                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      globalI,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 36,
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
                );
              }),
            ),
          ),
        ],
      ),
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
class _TopicNavButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TopicNavButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: BwbTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: BwbTheme.primary,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
