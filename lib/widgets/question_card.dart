import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/choice.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import 'choice_tile.dart';
import 'code_block_view.dart';

class QuestionCard extends StatelessWidget {
  final Question question;
  final int index;

  /// The position of this question in the full flat question list (0-based).
  /// Used to build stable widget keys that are guaranteed unique even when
  /// the server returns empty or duplicate question/choice IDs.
  /// Required for live quiz screens; optional (unused) in read-only result views.
  final int? globalIndex;

  final bool readOnly;
  final bool? isCorrect; // for results
  final VoidCallback? onSingleChoiceSelected;

  const QuestionCard({
    super.key,
    required this.question,
    required this.index,
    this.globalIndex,
    this.readOnly = false,
    this.isCorrect,
    this.onSingleChoiceSelected,
  });

  // ── Stable key helpers ────────────────────────────────────────────────────
  //
  // The server may return empty strings or integer IDs like "1", "2", "3"
  // that repeat across questions (each question's choices are numbered from 1).
  // If we key widgets on question.id / choice.id alone, Flutter's element tree
  // can reuse the same widget for a different question — causing selections to
  // "bleed" or answers to appear pre-selected on a fresh question.
  //
  // Solution: always incorporate the global position (globalIndex) in every
  // key.  The global index is positionally guaranteed to be unique even when
  // all server IDs are empty strings.

  /// Returns a string that is unique per question across the whole quiz.
  /// Prefers the combination of globalIndex+id (most stable), falls back to
  /// just the global index when the id is blank, and uses the local index as
  /// a last resort when this card is rendered outside a paged quiz (results).
  String _stableQuestionKey() {
    final pos = globalIndex ?? index;
    final id = question.id;
    return id.isNotEmpty ? 'q${pos}_$id' : 'q$pos';
  }

  /// The key used for all AttemptState reads and writes for this question.
  ///
  /// IMPORTANT: we ALWAYS use the positionally-unique [_stableQuestionKey()],
  /// never the raw `question.id`. The server may return short integer-string
  /// IDs like "1", "2", "3" that repeat across many questions in a quiz
  /// (e.g. each topic re-uses the same choice numbering). If we keyed
  /// `AttemptState.selectedChoices` on those IDs, two unrelated questions
  /// with the same id would share a state slot — tapping a choice on
  /// question A would visually select the same choice id on question B
  /// ("auto-select" / "selection bleed" across questions).
  ///
  /// The real `question.id` is still used at submit time in
  /// `AttemptState._buildAnswers()` so the server payload stays correct —
  /// it just never touches the in-memory state map.
  String _resolvedId() => _stableQuestionKey();

  @override
  Widget build(BuildContext context) {
    final stableKey = _stableQuestionKey();
    final resolvedId = _resolvedId();

    // Use Selector so this card only rebuilds when its own question's
    // selected choices or flagged state change — NOT on every timer tick.
    //
    // All lookups use resolvedId, which is unique per question even when
    // the server returns empty or duplicate question IDs.
    return Selector<AttemptState, ({List<String> selected, bool isFlagged})>(
      selector: (_, state) => (
        selected: List<String>.unmodifiable(
          state.selectedChoices[resolvedId] ?? const [],
        ),
        isFlagged: state.flaggedQuestions.contains(resolvedId),
      ),
      // Only rebuild when the content actually changes, not on reference churn.
      shouldRebuild: (prev, next) =>
          prev.isFlagged != next.isFlagged ||
          !_listEquals(prev.selected, next.selected),
      builder: (context, data, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Question header: number + flag + marks ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Q${index + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (!readOnly) ...[
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(
                            data.isFlagged
                                ? Icons.flag
                                : Icons.flag_outlined,
                            color: data.isFlagged
                                ? Colors.orange
                                : BwbTheme.muted,
                            size: 22,
                          ),
                          onPressed: () {
                            context
                                .read<AttemptState>()
                                .toggleFlagged(resolvedId);
                          },
                          tooltip: 'Flag Question',
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${question.marks.toStringAsFixed(question.marks.truncateToDouble() == question.marks ? 0 : 1)} mark${question.marks != 1 ? 's' : ''}',
                    style:
                        const TextStyle(fontSize: 13, color: BwbTheme.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── Question text ─────────────────────────────────────────────
              Text(question.text,
                  style: const TextStyle(fontSize: 16, height: 1.4)),
              if (question.qtype == QuestionType.mcqMulti && !readOnly) ...[
                const SizedBox(height: 6),
                const Text(
                  'This question may have more than one correct option.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF059669),
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              // ── Optional code snippet ─────────────────────────────────────
              // During a live quiz (readOnly=false) we hide it for coding-type
              // questions because `code` may contain the reference solution.
              // In review/result mode (readOnly=true) we always show it.
              if (question.code.isNotEmpty &&
                  (readOnly ||
                      question.qtype != QuestionType.coding)) ...[
                const SizedBox(height: 12),
                CodeBlockView(code: question.code),
              ],
              const SizedBox(height: 16),
              // ── Choices / Coding ──────────────────────────────────────────
              if (question.qtype == QuestionType.coding)
                _buildCodingSection(context)
              else
                _buildChoices(context, data.selected, stableKey, resolvedId),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChoices(
    BuildContext context,
    List<String> selected,
    String stableQuestionKey,
    String resolvedId,
  ) {
    return Column(
      children: [
        for (int ci = 0; ci < question.choices.length; ci++)
          _buildChoiceTile(
            context,
            question.choices[ci],
            ci,
            selected,
            stableQuestionKey,
            resolvedId,
          ),
      ],
    );
  }

  Widget _buildChoiceTile(
    BuildContext context,
    Choice choice,
    int choiceIndex,
    List<String> selected,
    String stableQuestionKey,
    String resolvedId,
  ) {
    // Pick the choice identifier we write into AttemptState.  Prefer the
    // server's choice.id (it's unique within the question).  When the
    // server returned an empty string we fall back to a positional key —
    // otherwise every choice on this question would share '' and
    // `selected.contains('')` would mark them ALL as selected, causing
    // the "all options appear pre-selected" symptom.
    final resolvedChoiceId = choice.id.isNotEmpty
        ? choice.id
        : '${stableQuestionKey}_c$choiceIndex';

    final tileState = _resolveTileState(choice, resolvedChoiceId, selected);

    // Key is position-based (stableQuestionKey + choice index), NOT tied to
    // tileState.  Including tileState in the key would destroy and recreate
    // the widget on every tap, which:
    //   (a) flickers the UI during the AnimatedContainer transition, and
    //   (b) can leave a dangling gesture in the pipeline that fires on the
    //       next question after the 400 ms auto-advance slides the page.
    return ChoiceTile(
      key: ValueKey('${stableQuestionKey}_c$choiceIndex'),
      choice: choice,
      state: tileState,
      onTap: readOnly
          ? null
          : () {
              final state = context.read<AttemptState>();
              if (question.qtype == QuestionType.mcqSingle ||
                  question.qtype == QuestionType.codeMcq) {
                // Use resolvedId so blank-ID questions write to their own
                // isolated slot, not a shared '' key.
                state.selectSingleChoice(resolvedId, resolvedChoiceId);
                onSingleChoiceSelected?.call();
              } else {
                state.toggleMultiChoice(resolvedId, resolvedChoiceId);
              }
            },
    );
  }

  ChoiceTileState _resolveTileState(
    Choice choice,
    String resolvedChoiceId,
    List<String> selected,
  ) {
    if (readOnly) {
      // Read-only (result screen) — the API populates is_correct at this
      // point, so we can show green/red badges.  Match against the real
      // choice.id since the server returns answers keyed by the real ID.
      if (choice.isCorrect == true) {
        return ChoiceTileState.correct;
      } else if (selected.contains(choice.id) && choice.isCorrect == false) {
        return ChoiceTileState.wrong;
      } else {
        return ChoiceTileState.unselected;
      }
    }
    // Match against the same ID we write (real id, or positional fallback
    // when the server gave us an empty string).  Without this fallback a
    // single empty-id choice would match `selected.contains('')` and mark
    // every other empty-id choice on the same question as selected too.
    return selected.contains(resolvedChoiceId)
        ? ChoiceTileState.selected
        : ChoiceTileState.unselected;
  }

  Widget _buildCodingSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BwbTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Coding Question',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Tap "Open Editor" to write your solution.',
            style: TextStyle(color: BwbTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // Pass (question, globalIndex) so the coding screen can
              // address the same positional state key the rest of the
              // quiz uses — see AttemptState.stateKeyFor. The args are
              // packed in a List so we don't need a shared public type.
              Navigator.of(context).pushNamed(
                '/coding',
                arguments: <Object>[question, globalIndex ?? index],
              );
            },
            child: const Text('Open Editor'),
          ),
        ],
      ),
    );
  }
}

// Inline list equality helper — avoids importing collection package.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
