import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../state/attempt_state.dart';
import '../theme.dart';

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

  // Fade-in for the whole dialog
  late final AnimationController _fadeController;

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

    // Fade in dialog
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

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
    // (currently always visible when on a final warning or while suspended)

    return PopScope(
      canPop: false,
      // Stack-based overlay so the warning card sits on top of a fully
      // opaque barrier — the rest of the app must not be visible while
      // a violation is being acknowledged.
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xCC000000)),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: _buildCard(isFinalWarning),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    bool isFinalWarning,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: (isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.wrong).withValues(alpha: 0.15),
            blurRadius: 40,
            spreadRadius: 10,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: (isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.wrong).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Lottie Error / Warning Icon with shake effect & glow
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.wrong).withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 110,
                      child: Lottie.asset(
                        'assets/json/error.json',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                isFinalWarning
                    ? 'ASSESSMENT TERMINATED'
                    : 'SECURITY VIOLATION',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.text,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Reason Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: BwbTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BwbTheme.border),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.reason,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: BwbTheme.text,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFinalWarning
                          ? 'Maximum violations reached. Your test is being automatically submitted.'
                          : 'Opening other apps, overlays, notification shade, or leaving fullscreen is prohibited.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: BwbTheme.muted,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (isFinalWarning || _suspensionRemaining > 0)
                      ? null
                      : widget.onDismiss,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFinalWarning ? const Color(0xFF7F1D1D) : BwbTheme.primary,
                    disabledBackgroundColor: BwbTheme.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isFinalWarning
                        ? 'Submitting Test...'
                        : _suspensionRemaining > 0
                            ? 'Wait ${_suspensionRemaining}s to Resume'
                            : 'I Understand — Resume',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: (isFinalWarning || _suspensionRemaining > 0)
                          ? BwbTheme.muted
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

