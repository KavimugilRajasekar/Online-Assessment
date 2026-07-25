import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../state/attempt_state.dart';
import '../theme.dart';

class TimerBar extends StatefulWidget {
  final int totalSeconds;

  const TimerBar({super.key, required this.totalSeconds});

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar>
    with SingleTickerProviderStateMixin {
  // Bar position is driven ENTIRELY by state.remainingSeconds (the same
  // integer the text shows) plus a fractional-second offset from
  // wall-clock. This guarantees that:
  //   - The bar is always in lockstep with the countdown text.
  //   - The Quiz screen and Review screen show IDENTICAL bar positions
  //     for the same remainingSeconds — no "reset" when switching.
  //   - The bar animates smoothly between integer-second boundaries.
  //
  // We deliberately do NOT cache a separate "_monotonicElapsed" that
  // can drift ahead of the state (which was the previous bug: the
  // ticker would advance the cached value past what the state said,
  // so the Review screen — which seeded fresh from the state — would
  // visibly "refill" the bar on entry).
  double _fractionalSecond = 0.0;
  int _lastRemainingSec = 0;
  int _totalSec = 0;

  // Tracks when the current integer second started, so we can compute
  // the fractional offset within it. Reset every time the state
  // decrements remainingSeconds.
  DateTime _secondStartedAt = DateTime.now().toUtc();

  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();

    final state = context.read<AttemptState>();
    _captureAttempt(state);

    _ticker =
        AnimationController(vsync: this, duration: const Duration(days: 1))
          ..addListener(() {
            _onTick(Duration.zero);
          })
          ..repeat();
  }

  @override
  void didUpdateWidget(covariant TimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // totalSeconds is now the frozen, authoritative denominator (see
    // AttemptState.totalSeconds). If a new value ever arrives here it should
    // only ever be the SAME frozen total re-passed down, never a live
    // recomputation from timestamps — otherwise Quiz/Review can disagree again.
    if (widget.totalSeconds != oldWidget.totalSeconds && widget.totalSeconds > 0) {
      _totalSec = widget.totalSeconds;
    }
  }

  void _captureAttempt(AttemptState state) {
    final attempt = state.attempt;
    if (attempt == null) {
      _totalSec = 0;
      _fractionalSecond = 0.0;
      _lastRemainingSec = 0;
      return;
    }
    // Use the frozen total from AttemptState (set once at attempt start),
    // NOT deadline.difference(started). Recomputing from those timestamps
    // is what caused Quiz and Review to disagree on "total" after a
    // violation penalty or resync touched the underlying timestamps.
    _totalSec = widget.totalSeconds;
    if (_totalSec <= 0) _totalSec = 0;
    final started = attempt.startedAtDateTime;
    _lastRemainingSec = state.remainingSeconds;
    _secondStartedAt = DateTime.now().toUtc();
    _fractionalSecond = 0.0;

    // Estimate how far we are into the current integer second. The
    // state's remainingSeconds is decremented once per second; the
    // exact moment of the last decrement is unknown, but we can infer
    // it from the difference between wall-clock elapsed and the
    // integer-second elapsed implied by remainingSeconds. This is
    // what makes the Quiz and Review screens show identical bar
    // positions at the instant the route is pushed: both compute the
    // same fractional offset from the same state value.
    if (_totalSec > 0 && _lastRemainingSec >= 0) {
      final now = DateTime.now().toUtc();
      final wallElapsedSec = now.difference(started).inMilliseconds / 1000.0;
      final stateElapsedSec = (_totalSec - _lastRemainingSec).toDouble();
      final frac = wallElapsedSec - stateElapsedSec;
      if (frac >= 0.0 && frac < 1.0) {
        _fractionalSecond = frac;
        // Backdate _secondStartedAt so the ticker continues from this
        // same offset rather than restarting from 0 (which would cause
        // the bar to "refill" for up to a second on the new screen).
        _secondStartedAt = now.subtract(
          Duration(milliseconds: (frac * 1000).round()),
        );
      }
    }
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final state = context.read<AttemptState>();
    final remaining = state.remainingSeconds;

    // If the state's remainingSeconds just decremented, reset the
    // fractional-second clock so the bar starts the new second from 0.
    if (remaining < _lastRemainingSec) {
      _lastRemainingSec = remaining;
      _secondStartedAt = DateTime.now().toUtc();
      _fractionalSecond = 0.0;
    } else if (remaining > _lastRemainingSec) {
      // Violation penalty or clock correction: jump forward to match.
      _lastRemainingSec = remaining;
      _secondStartedAt = DateTime.now().toUtc();
      _fractionalSecond = 0.0;
    }

    if (_totalSec <= 0) return;

    // Fractional progress through the current integer second.
    final msIntoSecond = DateTime.now()
        .toUtc()
        .difference(_secondStartedAt)
        .inMilliseconds;
    _fractionalSecond = (msIntoSecond / 1000.0).clamp(0.0, 1.0);

    // Trigger a rebuild so the bar animates.
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _format(int secs) {
    final minutes = secs ~/ 60;
    final seconds = secs % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Smoothly interpolates the bar color across the remaining progress:
  ///   full   → green
  ///   mid    → amber
  ///   low    → red
  Color _getColor(double progress) {
    if (progress >= 0.5) {
      final t = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFFF59E0B), // amber
        const Color(0xFF22C55E), // green
        t,
      )!;
    } else if (progress >= 0.2) {
      final t = ((progress - 0.2) / 0.3).clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFFEF4444), // red
        const Color(0xFFF59E0B), // amber
        t,
      )!;
    } else {
      return const Color(0xFFEF4444); // red
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttemptState>();
    final remaining = state.remainingSeconds;

    // The bar position is computed from state.remainingSeconds (the
    // authoritative integer) plus a fractional offset within the
    // current second. Both Quiz and Review screens read the same
    // state, so they show the same bar position at the same instant.
    final totalSec = _totalSec > 0 ? _totalSec : widget.totalSeconds;
    final elapsedSecExact = (totalSec - remaining) + _fractionalSecond;
    final elapsed = totalSec > 0
        ? (elapsedSecExact / totalSec).clamp(0.0, 1.0)
        : 0.0;

    final isCritical = remaining > 0 && (remaining / totalSec) <= 0.2;
    final progress = (1.0 - elapsed).clamp(0.0, 1.0);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    width: trackWidth,
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: const Color(0xFFE5E7EB)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: trackWidth * progress,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getColor(progress),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 14),

          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isCritical ? BwbTheme.wrong : BwbTheme.text,
            ),
            child: Text(_format(remaining)),
          ),
        ],
      ),
    );
  }
}
