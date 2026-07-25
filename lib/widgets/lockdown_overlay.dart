import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import 'bwb_button.dart';

class LockdownOverlayDialog extends StatefulWidget {
  final String reason;
  final VoidCallback onDismiss;

  const LockdownOverlayDialog({
    super.key,
    required this.reason,
    required this.onDismiss,
  });

  @override
  State<LockdownOverlayDialog> createState() => _LockdownOverlayDialogState();
}

class _LockdownOverlayDialogState extends State<LockdownOverlayDialog>
    with TickerProviderStateMixin {
  // Shake animation for the warning icon
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  // Pulse animation for the "SUSPENDED" badge
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Fade-in for the whole dialog
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // Suspension countdown timer (1/6 minute = 10 seconds)
  int _suspensionRemaining = 10;
  Timer? _suspensionTimer;

  @override
  void initState() {
    super.initState();

    // Shake: quick left-right on open
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    // Pulse: repeating scale for "SUSPENDED" badge
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade in dialog
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _fadeController.forward();
    _shakeController.forward();

    _startSuspensionTimer();
  }

  void _startSuspensionTimer() {
    _suspensionTimer?.cancel();
    _suspensionRemaining = 10; // 1/6 minute
    _suspensionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_suspensionRemaining > 0) {
          _suspensionRemaining--;
        } else {
          _suspensionTimer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _suspensionTimer?.cancel();
    _shakeController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read live violation state so counter updates without rebuilding
    final attemptState = context.watch<AttemptState>();
    final violationCount = attemptState.violationCount;
    final maxViolations = AttemptState.maxViolations;
    final isFinalWarning = violationCount >= maxViolations;

    // Show "SUSPENDED" badge
    final showSuspended = isFinalWarning || _suspensionRemaining > 0 || (violationCount % 3 == 0);

    return PopScope(
      canPop: false,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.wrong,
              width: 3,
            ),
            borderRadius: BorderRadius.zero,
          ),
          insetPadding: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Lottie Error / Warning Icon with shake effect
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  ),
                  child: SizedBox(
                    height: 100,
                    child: Lottie.asset(
                      'assets/json/cat_error.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // "SUSPENDED" animated badge
                if (showSuspended) ...[
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7F1D1D), Color(0xFFDC2626)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: BwbTheme.wrong.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.block_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            isFinalWarning ? 'SUSPENDED' : 'SUSPENDED (${_suspensionRemaining}s)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Title
                Text(
                  isFinalWarning
                      ? 'ASSESSMENT SUSPENDED'
                      : 'SECURITY VIOLATION DETECTED',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.wrong,
                    letterSpacing: 0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Animated violation counter badge
                _AnimatedViolationBadge(
                  violationCount: violationCount,
                  maxViolations: maxViolations,
                ),
                const SizedBox(height: 14),

                // Suspension countdown banner
                if (_suspensionRemaining > 0 && !isFinalWarning) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BwbTheme.wrong,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Suspended for 1/6 min (${_suspensionRemaining}s left)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: BwbTheme.wrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Reason
                Text(
                  widget.reason,
                  style: const TextStyle(
                      fontSize: 14, color: BwbTheme.text, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isFinalWarning
                      ? 'Maximum violations reached. Your test is being automatically submitted.'
                      : 'Opening other apps, overlays, notification shade, or leaving fullscreen is prohibited during the test.',
                  style: const TextStyle(fontSize: 12, color: BwbTheme.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: BwbButton(
                    label: isFinalWarning
                        ? 'Submitting Test...'
                        : _suspensionRemaining > 0
                            ? 'Suspended (Wait ${_suspensionRemaining}s)'
                            : 'I Understand — Resume Test',
                    onPressed: (isFinalWarning || _suspensionRemaining > 0)
                        ? null
                        : widget.onDismiss,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated counter badge that transitions from old count → new count.
class _AnimatedViolationBadge extends StatefulWidget {
  final int violationCount;
  final int maxViolations;
  const _AnimatedViolationBadge(
      {required this.violationCount, required this.maxViolations});

  @override
  State<_AnimatedViolationBadge> createState() =>
      _AnimatedViolationBadgeState();
}

class _AnimatedViolationBadgeState extends State<_AnimatedViolationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideOut;
  late Animation<double> _slideIn;
  int _displayed = 0;

  @override
  void initState() {
    super.initState();
    _displayed = widget.violationCount;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideOut = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5)));
    _slideIn = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)));
  }

  @override
  void didUpdateWidget(_AnimatedViolationBadge old) {
    super.didUpdateWidget(old);
    if (old.violationCount != widget.violationCount) {
      _controller.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _displayed = widget.violationCount);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction =
        (widget.violationCount / widget.maxViolations).clamp(0.0, 1.0);
    final barColor = fraction >= 1.0
        ? const Color(0xFF7F1D1D)
        : fraction >= 0.6
            ? BwbTheme.wrong
            : const Color(0xFFF59E0B);

    return Column(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final isAnimating = _controller.isAnimating;
            return ClipRect(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: BwbTheme.wrong.withValues(alpha: 0.1),
                  border: Border.all(color: BwbTheme.wrong),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: isAnimating && _controller.value < 0.5
                    ? Transform.translate(
                        offset: Offset(0, _slideOut.value),
                        child: Opacity(
                          opacity: math.max(0, 1 - _controller.value * 4),
                          child: _badgeText(_displayed),
                        ),
                      )
                    : Transform.translate(
                        offset: Offset(0, _controller.isAnimating ? _slideIn.value : 0),
                        child: Opacity(
                          opacity: _controller.isAnimating
                              ? math.min(1, (_controller.value - 0.5) * 4)
                              : 1.0,
                          child: _badgeText(widget.violationCount),
                        ),
                      ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // Progress bar showing violations used
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, val, _) => LinearProgressIndicator(
              value: val,
              minHeight: 5,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _badgeText(int count) => Text(
        'Violation $count of ${widget.maxViolations}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: BwbTheme.wrong,
        ),
      );
}
