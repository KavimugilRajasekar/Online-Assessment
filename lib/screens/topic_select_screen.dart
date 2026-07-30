import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../models/quiz.dart';
import '../services/attempt_service.dart';
import '../services/attempt_store.dart';
import '../state/quiz_state.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import '../widgets/bwb_button.dart';
import '../widgets/bwb_card.dart';

class TopicSelectScreen extends StatefulWidget {
  const TopicSelectScreen({super.key});

  @override
  State<TopicSelectScreen> createState() => _TopicSelectScreenState();
}

class _TopicSelectScreenState extends State<TopicSelectScreen>
    with SingleTickerProviderStateMixin {
  bool _starting = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();

  late final AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final quiz = context.read<QuizState>().selectedQuiz;
      if (quiz != null) context.read<QuizState>().loadTopics(quiz.id);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _lottieController.dispose();
    super.dispose();
  }

  Future<void> _startQuiz(Quiz quiz) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _starting = true);
    try {
      final attempt = await AttemptService.instance.startOrResumeAttempt(
        quiz.id,
        candidateName: _nameController.text.trim(),
        candidateId: _idController.text.trim(),
      );
      await AttemptStore.instance.save(quiz.id, attempt.id);
      if (mounted) {
        context.read<AttemptState>().setAttempt(attempt);
        Navigator.of(context).pushNamed('/quiz');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: BwbTheme.wrong,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _viewAnswerKey(Quiz quiz) async {
    setState(() => _starting = true);
    try {
      final savedAttemptId = await AttemptStore.instance.get(quiz.id);
      if (savedAttemptId != null) {
        final result = await AttemptService.instance.getResult(savedAttemptId);
        if (mounted) {
          context.read<AttemptState>().result = result;
          Navigator.of(context).pushNamed('/result');
          return;
        }
      }
      // If no local attempt saved, start/resume attempt to view answer details
      final attempt = await AttemptService.instance.startOrResumeAttempt(
        quiz.id,
      );
      if (mounted) {
        context.read<AttemptState>().setAttempt(attempt);
        Navigator.of(context).pushNamed('/quiz');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Answer Key Notice: $e'),
            backgroundColor: BwbTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizState = context.watch<QuizState>();
    final quiz = quizState.selectedQuiz;
    final totalQuestions = quizState.topics.fold<int>(
      0,
      (sum, t) => sum + t.questionCount,
    );
    final durationMins = quiz != null ? quiz.durationSeconds ~/ 60 : 0;

    return Scaffold(
      body: quiz == null
          ? const Center(child: Text('No quiz selected.'))
          : CustomScrollView(
              slivers: [
                // Gradient header
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1e3a8a), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          // Back button row
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                Expanded(
                                  child: Text(
                                    quiz.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: BwbTheme.fontFamily,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Lottie animation
                          SizedBox(
                            height: 120,
                            child: Lottie.asset(
                              'assets/json/cat_cloud.json',
                              controller: _lottieController,
                              onLoaded: (composition) {
                                _lottieController
                                  ..duration = composition.duration
                                  ..repeat();
                              },
                              fit: BoxFit.contain,
                            ),
                          ),
                          // Stats chips
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _StatChip(
                                  icon: Icons.timer_outlined,
                                  label: '$durationMins min',
                                ),
                                const SizedBox(width: 12),
                                _StatChip(
                                  icon: Icons.quiz_outlined,
                                  label: '$totalQuestions Qs',
                                ),
                                const SizedBox(width: 12),
                                _StatChip(
                                  icon: Icons.lock_clock_outlined,
                                  label: 'Strict Mode',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Form body
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Candidate Details Card
                          _SectionLabel(label: 'Your Details'),
                          const SizedBox(height: 10),
                          BwbCard(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name *',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (val) =>
                                      val == null || val.trim().isEmpty
                                      ? 'Please enter your name'
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _idController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(
                                    labelText: 'Roll Number *',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (val) =>
                                      val == null || val.trim().isEmpty
                                      ? 'Please enter Roll Number'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Instructions
                          _SectionLabel(label: 'Instructions'),
                          const SizedBox(height: 10),
                          BwbCard(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                _Instruction(
                                  number: '1',
                                  text:
                                      'Do NOT switch to other applications, browser tabs, or windows during the assessment.',
                                ),
                                _Instruction(
                                  number: '2',
                                  text:
                                      'Do NOT minimize, close, or refresh the application while the assessment is in progress.',
                                ),
                                _Instruction(
                                  number: '3',
                                  text:
                                      'Do NOT use mobile phones, AI tools, search engines, or any unauthorized resources.',
                                ),
                                _Instruction(
                                  number: '4',
                                  text:
                                      'Any attempt to leave the assessment screen or violate these rules may result in automatic submission or disqualification.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Topics
                          if (quizState.topics.isNotEmpty) ...[
                            _SectionLabel(label: 'Topics Covered'),
                            const SizedBox(height: 10),
                            ...quizState.topics.map(
                              (topic) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: BwbCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: BwbTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          topic.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          '${topic.questionCount} Qs',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: BwbTheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          const SizedBox(height: 8),
                          // Start or View Answer Key button
                          SizedBox(
                            width: double.infinity,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: quiz.answersPosted
                                  ? BwbButton(
                                      key: const ValueKey('view_answers'),
                                      label: 'View Answer Key & Report',
                                      onPressed: () => _viewAnswerKey(quiz),
                                    )
                                  : BwbButton(
                                      key: ValueKey(_starting),
                                      label: _starting
                                          ? 'Starting...'
                                          : 'Start Assessment',
                                      onPressed: _starting
                                          ? null
                                          : () => _startQuiz(quiz),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: BwbTheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: BwbTheme.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: BwbTheme.text,
          ),
        ),
      ],
    );
  }
}

class _Instruction extends StatelessWidget {
  final String number;
  final String text;
  const _Instruction({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: BwbTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: BwbTheme.muted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
