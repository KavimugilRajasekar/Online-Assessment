import 'package:flutter/material.dart';
import '../theme.dart';
import 'bwb_button.dart';

class LockdownOverlayDialog extends StatelessWidget {
  final String reason;
  final int violationCount;
  final int maxViolations;
  final VoidCallback onDismiss;

  const LockdownOverlayDialog({
    super.key,
    required this.reason,
    required this.violationCount,
    required this.maxViolations,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isFinalWarning = violationCount >= maxViolations;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: BwbTheme.wrong, width: 3),
          borderRadius: BorderRadius.zero,
        ),
        insetPadding: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: BwbTheme.wrong, size: 56),
              const SizedBox(height: 12),
              const Text(
                'SECURITY VIOLATION DETECTED',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: BwbTheme.wrong,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: BwbTheme.wrong.withValues(alpha: 0.1),
                  border: Border.all(color: BwbTheme.wrong),
                ),
                child: Text(
                  'Violation $violationCount of $maxViolations',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: BwbTheme.wrong,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                reason,
                style: const TextStyle(
                    fontSize: 14, color: BwbTheme.text, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isFinalWarning
                    ? 'Maximum violations reached. Your test is being automatically submitted.'
                    : 'Opening other apps, overlays, notification shade, or leaving fullscreen is prohibited during the test.',
                style:
                    const TextStyle(fontSize: 12, color: BwbTheme.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: BwbButton(
                  label: isFinalWarning
                      ? 'Submitting Test...'
                      : 'I Understand — Resume Test',
                  onPressed: isFinalWarning ? null : onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
