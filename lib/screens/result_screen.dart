import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../models/answer.dart';
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

  String _formatDuration(int totalSecs) {
    if (totalSecs <= 0) return '0s';
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    if (s > 0 || parts.isEmpty) parts.add('${s}s');
    return parts.join(' ');
  }

  /// True when every non-coding answer is still pending (isCorrect == null).
  /// This happens when the server withheld choice.isCorrect during the quiz
  /// (anti-cheat) and the background sync hasn't come back yet.
  bool _allGradesPending(QuizResult result) {
    final mcqAnswers = result.answers
        .where((ar) => ar.question.qtype != QuestionType.coding);
    if (mcqAnswers.isEmpty) return false;
    return mcqAnswers.every((ar) => ar.answer.isCorrect == null);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final result = state.result;

    // result is set synchronously inside submitAndPush() before navigation
    // fires, so this should never be null from the normal quiz→result flow.
    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final serverSyncing = !state.serverSyncDone && !state.serverSyncFailed;
    final serverFailed = state.serverSyncFailed;

    // Grades are pending only while active sync is running and all MCQ answers are ungraded.
    // In offline mode (serverFailed), we ALWAYS display the locally evaluated score!
    final gradesPending = serverSyncing && _allGradesPending(result);

    final scorePercent = (result.totalMarks > 0)
        ? ((result.score / result.totalMarks * 100).clamp(0.0, 100.0))
        : 0.0;
    final scoreColor =
        gradesPending ? BwbTheme.primary : _scoreColor(scorePercent);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
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
                      // Lottie animation
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
                        gradesPending
                            ? 'Submitted!'
                            : _scoreLabel(scorePercent),
                        style: const TextStyle(
                          fontFamily: BwbTheme.fontFamily,
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Score card ─────────────────────────────────────────
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ScoreStat(
                              label: 'Your Score',
                              // Show dash while waiting for server grades so
                              // we don't show a misleading 0.
                              value: gradesPending
                                  ? '—'
                                  : result.score.toStringAsFixed(1),
                              color: scoreColor,
                            ),
                            Container(
                                height: 50,
                                width: 1,
                                color: BwbTheme.border),
                            _ScoreStat(
                              label: 'Total Marks',
                              value: result.totalMarks.toStringAsFixed(1),
                              color: BwbTheme.muted,
                            ),
                            Container(
                                height: 50,
                                width: 1,
                                color: BwbTheme.border),
                            _ScoreStat(
                              label: 'Percentage',
                              value: gradesPending
                                  ? '—'
                                  : '${scorePercent.toStringAsFixed(0)}%',
                              color: scoreColor,
                            ),
                          ],
                        ),
                      ),

                      // ── Time used chip ─────────────────────────────────────
                      if (state.timeUsedSeconds > 0) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Completed in ${_formatDuration(state.timeUsedSeconds)}'
                                    '${state.quizTotalSeconds > 0 ? '  /  ${_formatDuration(state.quizTotalSeconds)}' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.violationCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.security_outlined,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Violations: ${state.violationCount}/${AttemptState.maxViolations}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],

                      // ── Small syncing chip — only shown when grades are
                      //    already available locally (e.g. server returned
                      //    isCorrect during quiz) but the push is still
                      //    in flight.
                      if (serverSyncing && !gradesPending) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Syncing…',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Grades pending / failed banner ───────────────────────────────
          // Shown prominently below the header when the server is still
          // grading (gradesPending) or the sync failed entirely.
          if (gradesPending || serverFailed)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _SyncBanner(isFailed: serverFailed),
              ),
            ),

          // ── Answer review ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  ...result.answers
                      .asMap()
                      .entries
                      .map((e) => _buildAnswerCard(e.key, e.value)),
                  const SizedBox(height: 24),
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

  Widget _buildAnswerCard(int questionIndex, AnswerResult ar) {
    final q = ar.question;
    final a = ar.answer;
    final isCoding = q.qtype == QuestionType.coding;

    // Per-question pending: server hasn't returned isCorrect yet
    final isPending = !isCoding && a.isCorrect == null;

    Color borderColor;
    Color statusBg;
    Widget statusIcon;
    String statusText;
    Color statusTextColor;

    if (isCoding) {
      borderColor = BwbTheme.border;
      statusBg = const Color(0xFFF1F5F9);
      statusIcon = const Icon(Icons.code, size: 16, color: BwbTheme.muted);
      statusText = 'Manual Review';
      statusTextColor = BwbTheme.muted;
    } else if (isPending) {
      borderColor = const Color(0xFFD1D5DB);
      statusBg = const Color(0xFFF3F4F6);
      statusIcon = const Icon(Icons.hourglass_top_rounded,
          size: 16, color: Color(0xFF6B7280));
      statusText = a.selectedChoiceIds.isEmpty ? 'Not answered' : 'Pending';
      statusTextColor = const Color(0xFF6B7280);
    } else if (a.isCorrect == true) {
      borderColor = BwbTheme.correct;
      statusBg = const Color(0xFFD1FAE5);
      statusIcon = const Icon(Icons.check_circle_rounded,
          size: 16, color: BwbTheme.correct);
      statusText = 'Correct';
      statusTextColor = BwbTheme.correct;
    } else {
      borderColor =
          a.selectedChoiceIds.isEmpty ? BwbTheme.border : BwbTheme.wrong;
      statusBg = a.selectedChoiceIds.isEmpty
          ? const Color(0xFFF1F5F9)
          : const Color(0xFFFEE2E2);
      statusIcon = a.selectedChoiceIds.isEmpty
          ? const Icon(Icons.remove_circle_outline,
              size: 16, color: BwbTheme.muted)
          : const Icon(Icons.cancel_rounded,
              size: 16, color: BwbTheme.wrong);
      statusText =
          a.selectedChoiceIds.isEmpty ? 'Not answered' : 'Incorrect';
      statusTextColor =
          a.selectedChoiceIds.isEmpty ? BwbTheme.muted : BwbTheme.wrong;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
              // ── Question header ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8, top: 1),
                    decoration: BoxDecoration(
                      color: BwbTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Q${questionIndex + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: BwbTheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(q.text,
                        style:
                            const TextStyle(fontSize: 14, height: 1.4)),
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

              // ── Code snippet on question ─────────────────────────────────
              if (q.code.isNotEmpty && !isCoding) ...[
                const SizedBox(height: 8),
                CodeBlockView(code: q.code),
              ],

              // ── Choices ─────────────────────────────────────────────
              if (!isCoding && q.choices.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildResultChoices(q, a, questionIndex),
              ],

              // ── Coding answer ────────────────────────────────────────────
              if (isCoding) ...[
                const SizedBox(height: 8),
                const Text('Your solution:',
                    style:
                        TextStyle(fontSize: 12, color: BwbTheme.muted)),
                const SizedBox(height: 4),
                a.codeText.isNotEmpty
                    ? CodeBlockView(code: a.codeText)
                    : const Text('(no code submitted)',
                        style: TextStyle(
                            color: BwbTheme.muted, fontSize: 12)),
                const SizedBox(height: 4),
                const Text(
                  'Coding answers are reviewed manually.',
                  style: TextStyle(fontSize: 11, color: BwbTheme.muted),
                ),
              ],

              const SizedBox(height: 10),

              // ── Footer: status + marks ───────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isCoding)
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusTextColor,
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

              // ── Explanation ──────────────────────────────────────────────
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

  Widget _buildResultChoices(Question q, Answer a, int questionIndex) {
    final selectedIds = a.selectedChoiceIds.toSet();
    final hasCorrectnessData = q.choices.any((c) => c.isCorrect != null);

    final stateKey = q.id.isNotEmpty
        ? 'q${questionIndex}__${q.id}'
        : 'q$questionIndex';

    return Column(
      children: q.choices.asMap().entries.map((entry) {
        final ci = entry.key;
        final choice = entry.value;

        final resolvedChoiceId =
            choice.id.isNotEmpty ? choice.id : '${stateKey}_c$ci';

        final isSelected = selectedIds.contains(choice.id) ||
            selectedIds.contains(resolvedChoiceId);
        final isCorrectChoice = choice.isCorrect == true;

        ChoiceTileState tileState;
        String? badgeText;
        Color? badgeBgColor;
        Color? badgeTextColor;

        if (!hasCorrectnessData) {
          if (isSelected) {
            tileState = ChoiceTileState.selected;
            badgeText = '• Your Selection';
            badgeBgColor = const Color(0xFFDBEAFE);
            badgeTextColor = const Color(0xFF1E40AF);
          } else {
            tileState = ChoiceTileState.unselected;
          }
        } else if (isSelected && isCorrectChoice) {
          tileState = ChoiceTileState.correct;
          badgeText = '✓ Your Selection — Correct';
          badgeBgColor = const Color(0xFFD1FAE5);
          badgeTextColor = const Color(0xFF047857);
        } else if (isSelected && !isCorrectChoice) {
          tileState = ChoiceTileState.wrong;
          badgeText = '✗ Your Selection — Incorrect';
          badgeBgColor = const Color(0xFFFEE2E2);
          badgeTextColor = const Color(0xFFB91C1C);
        } else if (!isSelected && isCorrectChoice) {
          tileState = ChoiceTileState.correct;
          badgeText = '★ Correct Answer';
          badgeBgColor = const Color(0xFFE0F2FE);
          badgeTextColor = const Color(0xFF0369A1);
        } else {
          tileState = ChoiceTileState.unselected;
        }

        return ChoiceTile(
          key: ValueKey('result_${stateKey}_${ci}_${tileState.name}'),
          choice: choice,
          state: tileState,
          badgeText: badgeText,
          badgeBgColor: badgeBgColor,
          badgeTextColor: badgeTextColor,
          onTap: null,
        );
      }).toList(),
    );
  }
}

// ── Sync status banner ─────────────────────────────────────────────────────────
// Shown when the server withheld grades during the quiz and the background
// push is still in flight (or failed). Disappears once serverSyncDone.
class _SyncBanner extends StatelessWidget {
  final bool isFailed;
  const _SyncBanner({required this.isFailed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isFailed
            ? const Color(0xFFFFF7ED)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFailed
              ? const Color(0xFFFED7AA)
              : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          if (!isFailed)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BwbTheme.primary,
              ),
            )
          else
            const Icon(Icons.wifi_off_rounded,
                size: 20, color: Color(0xFFD97706)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFailed
                      ? 'Could not sync to server'
                      : 'Fetching your grades…',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isFailed
                        ? const Color(0xFFD97706)
                        : BwbTheme.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isFailed
                      ? 'Your answers were saved on this device. Connect to the internet to sync your result.'
                      : 'Your submission is saved. Scores and correct answers will appear once the server responds.',
                  style: const TextStyle(
                      fontSize: 12, color: BwbTheme.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Score stat widget ──────────────────────────────────────────────────────────
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
