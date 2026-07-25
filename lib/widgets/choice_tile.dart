import 'package:flutter/material.dart';
import '../models/choice.dart';
import '../theme.dart';

enum ChoiceTileState { unselected, selected, correct, wrong }

class ChoiceTile extends StatelessWidget {
  final Choice choice;
  final ChoiceTileState state;
  final VoidCallback? onTap;

  const ChoiceTile({
    super.key,
    required this.choice,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border;
    Color bg;
    Widget? trailing;

    switch (state) {
      case ChoiceTileState.correct:
        border = BwbTheme.correct;
        bg = BwbTheme.correct.withValues(alpha: 0.06);
        trailing = const Icon(Icons.check_circle, color: BwbTheme.correct, size: 20);
        break;
      case ChoiceTileState.wrong:
        border = BwbTheme.wrong;
        bg = BwbTheme.wrong.withValues(alpha: 0.06);
        trailing = const Icon(Icons.cancel, color: BwbTheme.wrong, size: 20);
        break;
      case ChoiceTileState.selected:
        border = BwbTheme.primary;
        bg = BwbTheme.primary.withValues(alpha: 0.1);
        trailing = null;
        break;
      case ChoiceTileState.unselected:
        border = BwbTheme.border;
        bg = BwbTheme.surface;
        trailing = null;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: state == ChoiceTileState.unselected ? 1 : 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(choice.text, style: const TextStyle(fontSize: 15)),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
