import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/quiz_state.dart';
import '../theme.dart';
import '../widgets/bwb_button.dart';
import '../widgets/bwb_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuizState>().loadQuizzes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final quizState = context.watch<QuizState>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/icons/online_assessment_logo.png',
              height: 32,
              width: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Text(
              'Online Assessment',
              style: TextStyle(
                fontFamily: BwbTheme.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero logo + welcome section
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Image.asset(
                      'assets/icons/online_assessment_logo.png',
                      height: 80,
                      width: 80,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome',
                      style: TextStyle(
                        fontFamily: BwbTheme.fontFamily,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a quiz below to begin your assessment.',
                      style: TextStyle(fontSize: 14, color: BwbTheme.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),

              // Quiz list
              if (quizState.loadState == QuizLoadState.loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  ),
                )
              else if (quizState.loadState == QuizLoadState.error)
                BwbCard(
                  borderColor: BwbTheme.wrong,
                  child: Text(
                    'Error: ${quizState.errorMessage}',
                    style: const TextStyle(color: BwbTheme.wrong),
                  ),
                )
              else if (quizState.quizzes.isEmpty)
                const BwbCard(child: Text('No quizzes available.'))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: quizState.quizzes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final quiz = quizState.quizzes[i];
                      final mins = quiz.durationSeconds ~/ 60;
                      return BwbCard(
                        child: Row(
                          children: [
                            // Quiz icon
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black),
                                color: const Color(0xFFF5F5F5),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontFamily: BwbTheme.fontFamily,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    quiz.title,
                                    style: const TextStyle(
                                      fontFamily: BwbTheme.fontFamily,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (quiz.description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      quiz.description,
                                      style: const TextStyle(
                                        color: BwbTheme.muted,
                                        fontSize: 12,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.topic_outlined,
                                          size: 13, color: BwbTheme.muted),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${quiz.topicCount} topic(s)',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: BwbTheme.muted),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.timer_outlined,
                                          size: 13, color: BwbTheme.muted),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$mins min',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: BwbTheme.muted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            BwbButton(
                              label: 'View',
                              onPressed: () {
                                quizState.selectQuiz(quiz);
                                Navigator.of(context).pushNamed('/topics');
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
