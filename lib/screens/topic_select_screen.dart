import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
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

class _TopicSelectScreenState extends State<TopicSelectScreen> {
  bool _starting = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final quiz = context.read<QuizState>().selectedQuiz;
      if (quiz != null) context.read<QuizState>().loadTopics(quiz.id);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
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
          SnackBar(content: Text('Error: $e')),
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

    final totalQuestions = quizState.topics.fold<int>(0, (sum, t) => sum + t.questionCount);
    final durationMins = quiz != null ? quiz.durationSeconds ~/ 60 : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(quiz?.title ?? 'Assessment Details'),
      ),
      body: SafeArea(
        child: quiz == null
            ? const Center(child: Text('No quiz selected.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Animation
                      Center(
                        child: SizedBox(
                          height: 120,
                          child: Lottie.asset('assets/json/cat_cloud.json'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Candidate Details Card
                      BwbCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Candidate Details',
                              style: TextStyle(
                                fontFamily: BwbTheme.fontFamily,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Please enter your information before starting the test.',
                              style: TextStyle(color: BwbTheme.muted, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name *',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty ? 'Please enter your name' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _idController,
                              decoration: const InputDecoration(
                                labelText: 'Roll Number / Email ID *',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty ? 'Please enter Roll No or Email' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Assessment Overview & How Questions will be Attended Card
                      BwbCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'How You Will Attend Questions',
                              style: TextStyle(
                                fontFamily: BwbTheme.fontFamily,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18, color: BwbTheme.primary),
                                const SizedBox(width: 8),
                                Text('Duration: $durationMins Minutes', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.quiz_outlined, size: 18, color: BwbTheme.primary),
                                const SizedBox(width: 8),
                                Text('Total Questions: $totalQuestions', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              children: [
                                Icon(Icons.lock_clock_outlined, size: 18, color: BwbTheme.primary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Strict Mode: Status bar & notifications locked during assessment.',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            const Text(
                              'Instructions:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '1. Each page displays 1 question at a time.\n'
                              '2. You can navigate between questions, select your answers, or type code solutions.\n'
                              '3. On the final question page, click "Submit Quiz" to record your score.\n'
                              '4. Do not exit or minimize the app during the assessment.',
                              style: TextStyle(color: BwbTheme.muted, fontSize: 13, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Topic Breakdown
                      if (quizState.topics.isNotEmpty) ...[
                        const Text(
                          'Included Topics',
                          style: TextStyle(
                            fontFamily: BwbTheme.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...quizState.topics.map((topic) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: BwbCard(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(topic.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text('${topic.questionCount} Qs', style: const TextStyle(color: BwbTheme.muted)),
                                  ],
                                ),
                              ),
                            )),
                      ],

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: BwbButton(
                          label: _starting ? 'Starting Test...' : 'Start Assessment',
                          onPressed: _starting ? null : () => _startQuiz(quiz),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
