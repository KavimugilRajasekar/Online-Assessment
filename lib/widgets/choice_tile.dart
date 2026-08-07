import 'package:flutter/material.dart';
import '../models/choice.dart';
import '../theme.dart';

enum ChoiceTileState { unselected, selected, correct, wrong }

class ChoiceTile extends StatelessWidget {
  final Choice choice;
  final ChoiceTileState state;
  final VoidCallback? onTap;
  final String? badgeText;
  final Color? badgeBgColor;
  final Color? badgeTextColor;

  const ChoiceTile({
    super.key,
    required this.choice,
    required this.state,
    this.onTap,
    this.badgeText,
    this.badgeBgColor,
    this.badgeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    Color border;
    Color bg;
    Widget? trailing;

    switch (state) {
      case ChoiceTileState.correct:
        border = const Color(0xFF059669);
        bg = const Color(0xFFECFDF5);
        trailing = const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20);
        break;
      case ChoiceTileState.wrong:
        border = const Color(0xFFDC2626);
        bg = const Color(0xFFFEF2F2);
        trailing = const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 20);
        break;
      case ChoiceTileState.selected:
        border = BwbTheme.primary;
        bg = BwbTheme.primary.withValues(alpha: 0.08);
        trailing = const Icon(Icons.radio_button_checked, color: BwbTheme.primary, size: 20);
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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: border,
            width: state == ChoiceTileState.unselected ? 1 : 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: (state == ChoiceTileState.correct || state == ChoiceTileState.wrong)
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (badgeText != null && badgeText!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBgColor ?? border.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeTextColor ?? border,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
