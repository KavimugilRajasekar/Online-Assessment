import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/result.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import '../widgets/bwb_button.dart';
import '../widgets/choice_tile.dart';
import '../widgets/code_block_view.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  Color _scoreColor(double pct) {
    if (pct >= 75) return const Color(0xFF10B981);
    if (pct >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _scoreLabel(double pct) {
    if (pct >= 90) return 'Excellent!';
    if (pct >= 75) return 'Great Job!';
    if (pct >= 50) return 'Good Effort!';
    if (pct >= 40) return 'Keep Practicing!';
    return 'Better Luck Next Time!';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final result = state.result;

    if (result == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // When the server push is still in-flight, score = 0 and answers have no
    // correctness data yet.  Show a neutral "submitted" banner and hide the
    // per-question breakdown until we have real grades.
    final isPending = result.id.isEmpty;

    final scorePercent = result.totalMarks > 0 && !isPending
        ? (result.score / result.totalMarks * 100)
        : 0.0;
    final scoreColor =
        isPending ? BwbTheme.primary : _scoreColor(scorePercent);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scoreColor.withValues(alpha: 0.85), scoreColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    children: [
                      // Lottie present animation
                      SizedBox(
                        height: 150,
                        child: Lottie.asset(
                          'assets/json/present.json',
                          controller: _lottieController,
                          onLoaded: (composition) {
                            _lottieController
                              ..duration = composition.duration
                              ..forward().whenComplete(() {
                                if (mounted) {
                                  _lottieController.repeat(
                                      min: 0.7, max: 1.0, reverse: true);
                                }
                              });
                          },
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPending ? 'Submitted!' : _scoreLabel(scorePercent),
                        style: const TextStyle(
                          fontFamily: BwbTheme.fontFamily,
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Score arc card
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: isPending
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Syncing to server…',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: BwbTheme.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Your answers have been recorded.\nGrades will appear once confirmed.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: BwbTheme.muted,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ScoreStat(
                                    label: 'Your Score',
                                    value:
                                        result.score.toStringAsFixed(1),
                                    color: scoreColor,
                                  ),
                                  Container(
                                      height: 50,
                                      width: 1,
                                      color: BwbTheme.border),
                                  _ScoreStat(
                                    label: 'Total Marks',
                                    value: result.totalMarks
                                        .toStringAsFixed(1),
                                    color: BwbTheme.muted,
                                  ),
                                  Container(
                                      height: 50,
                                      width: 1,
                                      color: BwbTheme.border),
                                  _ScoreStat(
                                    label: 'Percentage',
                                    value:
                                        '${scorePercent.toStringAsFixed(0)}%',
                                    color: scoreColor,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Answer review
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isPending) ...[
                    const Row(
                      children: [
                        Icon(Icons.fact_check_outlined,
                            color: BwbTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Answer Review',
                          style: TextStyle(
                            fontFamily: BwbTheme.fontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...result.answers.map((ar) => _buildAnswerCard(ar)),
                    const SizedBox(height: 24),
                  ],
                  if (isPending) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BwbTheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: BwbTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        'The answer key and your detailed score will be available once the results are published by the administrator.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: BwbTheme.primary,
                            height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: BwbButton(
                      label: 'Back to Home',
                      onPressed: () => Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (r) => false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(AnswerResult ar) {
    final q = ar.question;
    final a = ar.answer;
    final isCoding = q.qtype == QuestionType.coding;

    Color borderColor;
    Color statusBg;
    Widget statusIcon;

    if (isCoding) {
      borderColor = BwbTheme.border;
      statusBg = const Color(0xFFF1F5F9);
      statusIcon =
          const Icon(Icons.code, size: 16, color: BwbTheme.muted);
    } else if (a.isCorrect == true) {
      borderColor = BwbTheme.correct;
      statusBg = const Color(0xFFD1FAE5);
      statusIcon = const Icon(Icons.check_circle_rounded,
          size: 16, color: BwbTheme.correct);
    } else {
      borderColor = BwbTheme.wrong;
      statusBg = const Color(0xFFFEE2E2);
      statusIcon =
          const Icon(Icons.cancel_rounded, size: 16, color: BwbTheme.wrong);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: statusIcon,
                  ),
                ],
              ),
              // Always show the question's code snippet in the result screen —
              // the "hide for coding type" rule only applies during the live quiz.
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
                        style:
                            TextStyle(color: BwbTheme.muted, fontSize: 12)),
                const SizedBox(height: 4),
                const Text(
                  'Coding answers are reviewed manually.',
                  style: TextStyle(fontSize: 11, color: BwbTheme.muted),
                ),
              ],
              // Choices — shown for mcqSingle, mcqMulti, and codeMcq.
              // Each choice is coloured: green if correct, red if the user
              // picked it and it's wrong, grey otherwise.
              if (!isCoding && q.choices.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...q.choices.map((choice) {
                  final userSelected = a.selectedChoiceIds.contains(choice.id);
                  ChoiceTileState tileState;
                  if (choice.isCorrect == true) {
                    tileState = ChoiceTileState.correct;
                  } else if (userSelected && choice.isCorrect == false) {
                    tileState = ChoiceTileState.wrong;
                  } else if (userSelected) {
                    // isCorrect is null (answer key not yet published) —
                    // still show what the user picked.
                    tileState = ChoiceTileState.selected;
                  } else {
                    tileState = ChoiceTileState.unselected;
                  }
                  return ChoiceTile(
                    choice: choice,
                    state: tileState,
                    onTap: null, // read-only
                  );
                }),
              ],
              const SizedBox(height: 10),
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
                        fontWeight: FontWeight.w700,
                        color: a.isCorrect == true
                            ? BwbTheme.correct
                            : (a.selectedChoiceIds.isEmpty
                                ? BwbTheme.muted
                                : BwbTheme.wrong),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${a.marksAwarded.toStringAsFixed(1)} / ${q.marks.toStringAsFixed(1)} marks',
                      style: const TextStyle(
                          fontSize: 12,
                          color: BwbTheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (q.explanation.isNotEmpty && !isCoding) ...[
                const Divider(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        q.explanation,
                        style: const TextStyle(
                            fontSize: 12,
                            color: BwbTheme.muted,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ScoreStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: BwbTheme.fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: BwbTheme.muted)),
      ],
    );
  }
}
