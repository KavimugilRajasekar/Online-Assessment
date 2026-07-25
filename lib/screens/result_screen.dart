import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import '../models/question.dart';
import '../models/result.dart';
import '../services/attempt_service.dart';
import '../services/attempt_store.dart';
import '../state/attempt_state.dart';
import '../state/quiz_state.dart';
import '../theme.dart';
import '../widgets/bwb_button.dart';
import '../widgets/bwb_card.dart';
import '../widgets/code_block_view.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final result = state.result;

    if (result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scorePercent = result.totalMarks > 0
        ? (result.score / result.totalMarks * 100)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results', style: TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Lottie Animation
            Center(
              child: SizedBox(
                height: 150,
                child: Lottie.asset('assets/json/present.json'),
              ),
            ),
            const SizedBox(height: 16),
            // Score card
            BwbCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Your Score',
                    style: TextStyle(fontSize: 14, color: BwbTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${result.score.toStringAsFixed(1)} / ${result.totalMarks.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${scorePercent.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 16, color: BwbTheme.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Per-Question Results',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...result.answers.map((ar) => _buildAnswerCard(ar)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: BwbButton(
                label: 'Retake Quiz',
                onPressed: () => _retake(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retake(BuildContext context) async {
    final quizState = context.read<QuizState>();
    final attemptState = context.read<AttemptState>();
    final quiz = quizState.selectedQuiz;
    attemptState.clear();
    await AttemptStore.instance.clear();
    if (quiz != null && context.mounted) {
      try {
        final attempt = await AttemptService.instance.startOrResumeAttempt(quiz.id);
        await AttemptStore.instance.save(quiz.id, attempt.id);
        if (context.mounted) {
          context.read<AttemptState>().setAttempt(attempt);
          Navigator.of(context).pushReplacementNamed('/quiz');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Widget _buildAnswerCard(AnswerResult ar) {
    final q = ar.question;
    final a = ar.answer;
    final isCoding = q.qtype == QuestionType.coding;

    Color borderColor;
    Widget statusIcon;
    if (isCoding) {
      borderColor = BwbTheme.border;
      statusIcon = const Icon(Icons.code, size: 18, color: BwbTheme.muted);
    } else if (a.isCorrect == true) {
      borderColor = BwbTheme.correct;
      statusIcon = const Icon(Icons.check_circle, size: 18, color: BwbTheme.correct);
    } else {
      borderColor = BwbTheme.wrong;
      statusIcon = const Icon(Icons.cancel, size: 18, color: BwbTheme.wrong);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BwbCard(
        borderColor: borderColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(q.text,
                      style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
                const SizedBox(width: 8),
                statusIcon,
              ],
            ),
            if (q.code.isNotEmpty) ...[
              const SizedBox(height: 8),
              CodeBlockView(code: q.code),
            ],
            if (isCoding) ...[
              const SizedBox(height: 8),
              const Text('Your solution:',
                  style: TextStyle(fontSize: 12, color: BwbTheme.muted)),
              const SizedBox(height: 4),
              a.codeText.isNotEmpty
                  ? CodeBlockView(code: a.codeText)
                  : const Text('(no code submitted)',
                      style: TextStyle(color: BwbTheme.muted, fontSize: 12)),
              const SizedBox(height: 4),
              const Text(
                'Note: Coding round is not auto-graded in v1.',
                style: TextStyle(fontSize: 11, color: BwbTheme.muted),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isCoding)
                  Text(
                    a.isCorrect == true
                        ? 'Correct'
                        : (a.selectedChoiceIds.isEmpty
                            ? 'Not answered'
                            : 'Incorrect'),
                    style: TextStyle(
                      fontSize: 12,
                      color: a.isCorrect == true
                          ? BwbTheme.correct
                          : (a.selectedChoiceIds.isEmpty
                              ? BwbTheme.muted
                              : BwbTheme.wrong),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Text(
                  '${a.marksAwarded.toStringAsFixed(1)} / ${q.marks.toStringAsFixed(1)} marks',
                  style: const TextStyle(fontSize: 12, color: BwbTheme.muted),
                ),
              ],
            ),
            if (q.explanation.isNotEmpty && !isCoding) ...[
              const Divider(height: 16),
              Text(
                q.explanation,
                style: const TextStyle(
                    fontSize: 12,
                    color: BwbTheme.muted,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
