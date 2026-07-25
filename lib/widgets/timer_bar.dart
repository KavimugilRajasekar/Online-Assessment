import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/attempt_state.dart';
import '../theme.dart';

class TimerBar extends StatelessWidget {
  final int totalSeconds;

  const TimerBar({super.key, required this.totalSeconds});

  String _format(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = context.watch<AttemptState>().remainingSeconds;
    final fraction = totalSeconds > 0 ? (remaining / totalSeconds).clamp(0.0, 1.0) : 0.0;
    final isUrgent = remaining <= 60;
    final barColor = isUrgent ? BwbTheme.wrong : BwbTheme.border;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1.0, end: fraction),
                duration: const Duration(seconds: 1),
                curve: Curves.linear,
                builder: (context, val, _) => LinearProgressIndicator(
                  value: val,
                  backgroundColor: const Color(0xFFE0E0E0),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  minHeight: 6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _format(remaining),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isUrgent ? BwbTheme.wrong : BwbTheme.text,
            ),
          ),
        ],
      ),
    );
  }
}
