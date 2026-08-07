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

  // Pulse animation for dots
  late final AnimationController _pulseController;

  // Fade-in for the whole dialog
  late final AnimationController _fadeController;

  // Suspension countdown — user must wait before they can dismiss
  int _suspensionRemaining = 10;
  Timer? _suspensionTimer;

  // Track the last violation count we've seen so we can detect a new
  // violation arriving while the dialog is already open.
  int _lastSeenViolationCount = 0;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Seed with the count as of dialog-open, read once via context.read
    // (safe in initState — it's a one-off lookup, not a subscription).
    // Without this it defaults to 0, so the very first build() sees
    // violationCount (e.g. 1) > 0 and redundantly re-triggers the shake +
    // restarts the 10s suspension countdown a second time on every open.
    _lastSeenViolationCount = context.read<AttemptState>().violationCount;

    _shakeController.forward();
    _startSuspensionTimer();
  }

  void _startSuspensionTimer() {
    _suspensionTimer?.cancel();
    _suspensionRemaining = 10;
    _suspensionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    // Read live from AttemptState so the counter updates automatically
    // when a new violation fires while this dialog is already open.
    final state = context.watch<AttemptState>();
    final violationNumber = state.violationCount;
    final maxViolations = AttemptState.maxViolations;

    // Detect a new violation arriving while we're already open — restart
    // the shake and reset the suspension countdown so the user must wait
    // again before dismissing.
    if (violationNumber > _lastSeenViolationCount) {
      _lastSeenViolationCount = violationNumber;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _shakeController
          ..reset()
          ..forward();
        _startSuspensionTimer();
      });
    }

    final isFinal = violationNumber >= maxViolations;
    final accentColor =
        isFinal ? const Color(0xFFDC2626) : BwbTheme.wrong;

    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xCC000000)),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: _buildCard(
                  violationNumber: violationNumber,
                  maxViolations: maxViolations,
                  isFinal: isFinal,
                  accentColor: accentColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required int violationNumber,
    required int maxViolations,
    required bool isFinal,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: 10,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
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
              // Warning icon with shake
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.2),
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
                isFinal ? 'QUIZ AUTO-SUBMITTED' : 'SECURITY VIOLATION',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // Violation counter dots — live count
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(maxViolations, (i) {
                  final filled = i < violationNumber;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? accentColor : Colors.transparent,
                      border: Border.all(
                        color:
                            filled ? accentColor : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),
              Text(
                isFinal
                    ? 'Maximum violations reached'
                    : 'Warning $violationNumber of $maxViolations',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 16),

              // Reason box
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
                      isFinal
                          ? 'Your quiz has been submitted automatically due to repeated violations.'
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

              // Action button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isFinal
                      ? widget.onDismiss
                      : (_suspensionRemaining > 0 ? null : widget.onDismiss),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isFinal ? accentColor : BwbTheme.primary,
                    disabledBackgroundColor: BwbTheme.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isFinal
                        ? 'View Result'
                        : (_suspensionRemaining > 0
                            ? 'Wait ${_suspensionRemaining}s to Resume'
                            : 'I Understand — Resume'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isFinal
                          ? Colors.white
                          : (_suspensionRemaining > 0
                              ? BwbTheme.muted
                              : Colors.white),
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
