import 'package:flutter_test/flutter_test.dart';
import 'package:online_assessment/state/attempt_state.dart';

void main() {
  group('AttemptState offline queue', () {
    test('isSubmitBlocked is false on fresh state', () {
      final state = AttemptState();
      expect(state.isSubmitBlocked, false);
      state.dispose();
    });
  });
}
