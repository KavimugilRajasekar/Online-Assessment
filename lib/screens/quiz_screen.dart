import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import '../widgets/question_card.dart';
import '../widgets/timer_bar.dart';
import '../widgets/bwb_button.dart';

import '../services/lockdown_service.dart';
import '../widgets/lockdown_overlay.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  bool _submitting = false;
  bool _showingViolationDialog = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);

    // Enable Kiosk Lockdown Mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LockdownService.instance.enableLockdown(onViolation: _handleViolation);
    });
  }

  @override
  void dispose() {
    LockdownService.instance.disableLockdown();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _handleViolation(String reason) {
    if (!mounted) return;
    final attemptState = context.read<AttemptState>();
    // Increment FIRST so the dialog shows the updated count
    attemptState.recordViolation(reason);

    if (!_showingViolationDialog) {
      _showingViolationDialog = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        // Provide AttemptState so the dialog can watch live violation count
        builder: (ctx) => ChangeNotifierProvider<AttemptState>.value(
          value: attemptState,
          child: LockdownOverlayDialog(
            reason: reason,
            onDismiss: () {
              _showingViolationDialog = false;
              Navigator.pop(ctx);
              // Re-enforce lockdown
              LockdownService.instance.enableLockdown(onViolation: _handleViolation);
            },
          ),
        ),
      ).then((_) {
        _showingViolationDialog = false;
      });
    }
    // Auto-submit is handled inside AttemptState.recordViolation()
  }

  Future<void> _autoSubmitOnViolation() async {
    final attemptState = context.read<AttemptState>();
    await attemptState.submit();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/result');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LockdownService.instance.handleLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkExpired();
    }
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
        content: Text('Quiz is in progress! You cannot leave or close the app until the quiz is submitted.'),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final pop = await _onWillPop();
        if (pop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quiz', style: TextStyle(fontWeight: FontWeight.bold)),
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
            // Offline indicator
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
            // Questions
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: questions.length,
                onPageChanged: (i) => attemptState.goToQuestion(i),
                itemBuilder: (context, i) {
                  return SingleChildScrollView(
                    child: QuestionCard(question: questions[i], index: i),
                  );
                },
              ),
            ),
            // Numbered pager
            _buildPager(attemptState, questions.length),
          ],
        ),
      ),
    );
  }

  Widget _buildPager(AttemptState state, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(count, (i) {
            final question = state.attempt!.questions[i];
            final hasAnswer =
                (state.selectedChoices[question.id]?.isNotEmpty ?? false) ||
                (state.codeAnswers[question.id]?.isNotEmpty ?? false);
            final isCurrent = i == state.currentQuestionIndex;
            return GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Colors.black
                      : (hasAnswer ? const Color(0xFFE0E0E0) : Colors.white),
                  border: Border.all(
                    color: Colors.black,
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
