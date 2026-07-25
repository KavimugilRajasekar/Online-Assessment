import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import 'choice_tile.dart';
import 'code_block_view.dart';

class QuestionCard extends StatelessWidget {
  final Question question;
  final int index;
  final bool readOnly;
  final bool? isCorrect; // for results
  final VoidCallback? onSingleChoiceSelected;

  const QuestionCard({
    super.key,
    required this.question,
    required this.index,
    this.readOnly = false,
    this.isCorrect,
    this.onSingleChoiceSelected,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final selected = state.selectedChoices[question.id] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question number + flag button + marks
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Q${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (!readOnly) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(
                        state.flaggedQuestions.contains(question.id)
                            ? Icons.flag
                            : Icons.flag_outlined,
                        color: state.flaggedQuestions.contains(question.id)
                            ? Colors.orange
                            : BwbTheme.muted,
                        size: 22,
                      ),
                      onPressed: () {
                        context.read<AttemptState>().toggleFlagged(question.id);
                      },
                      tooltip: 'Flag Question',
                    ),
                  ],
                ],
              ),
              Text(
                '${question.marks.toStringAsFixed(question.marks.truncateToDouble() == question.marks ? 0 : 1)} mark${question.marks != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: BwbTheme.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Question text
          Text(question.text, style: const TextStyle(fontSize: 16, height: 1.4)),
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
          // Code snippet (if any)
          if (question.code.isNotEmpty) ...[const SizedBox(height: 12), CodeBlockView(code: question.code)],
          const SizedBox(height: 16),
          // Choices / Coding
          if (question.qtype == QuestionType.coding)
            _buildCodingSection(context)
          else
            _buildChoices(context, selected),
        ],
      ),
    );
  }

  Widget _buildChoices(BuildContext context, List<String> selected) {
    return Column(
      children: question.choices.map((choice) {
        ChoiceTileState tileState;
        if (readOnly) {
          if (choice.isCorrect == true) {
            tileState = ChoiceTileState.correct;
          } else if (selected.contains(choice.id) && choice.isCorrect == false) {
            tileState = ChoiceTileState.wrong;
          } else {
            tileState = ChoiceTileState.unselected;
          }
        } else {
          tileState = selected.contains(choice.id)
              ? ChoiceTileState.selected
              : ChoiceTileState.unselected;
        }

        return ChoiceTile(
          choice: choice,
          state: tileState,
          onTap: readOnly
              ? null
              : () {
                  final state = context.read<AttemptState>();
                  if (question.qtype == QuestionType.mcqSingle ||
                      question.qtype == QuestionType.codeMcq) {
                    state.selectSingleChoice(question.id, choice.id);
                    onSingleChoiceSelected?.call();
                  } else {
                    state.toggleMultiChoice(question.id, choice.id);
                  }
                },
        );
      }).toList(),
    );
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
          const Text('Coding Question', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Tap "Open Editor" to write your solution.',
            style: const TextStyle(color: BwbTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/coding', arguments: question);
            },
            child: const Text('Open Editor'),
          ),
        ],
      ),
    );
  }
}
