import 'package:flutter_test/flutter_test.dart';
import 'package:online_assessment/models/attempt.dart';
import 'package:online_assessment/state/attempt_state.dart';

void main() {
  group('Lockdown & Anti-Cheat Proctoring Tests', () {
    late AttemptState attemptState;

    setUp(() {
      attemptState = AttemptState();
      final mockAttempt = Attempt(
        id: 'test_att_1',
        quizId: 'quiz_1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now().toIso8601String(),
        deadlineAt: DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
        totalMarks: 10,
        questionOrder: [],
        questions: [],
      );
      attemptState.setAttempt(mockAttempt);
    });

    tearDown(() {
      attemptState.dispose();
    });

    test('Initial violation count is 0', () {
      expect(attemptState.violationCount, 0);
      expect(attemptState.lastViolationReason, null);
    });

    test('Recording violations increments count', () {
      attemptState.recordViolation('Tab switch detected');
      expect(attemptState.violationCount, 1);
      expect(attemptState.lastViolationReason, 'Tab switch detected');

      attemptState.recordViolation('App switch attempt');
      expect(attemptState.violationCount, 2);
    });

    test('Reaching max violations triggers auto-submit threshold', () {
      attemptState.recordViolation('Violation 1');
      attemptState.recordViolation('Violation 2');
      expect(attemptState.violationCount, 2);

      attemptState.recordViolation('Violation 3 (Max)');
      expect(attemptState.violationCount, 3);
    });
  });
}
