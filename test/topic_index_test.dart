import 'package:flutter_test/flutter_test.dart';
import 'package:online_assessment/screens/topic_index.dart';

void main() {
  group('topic-switch math (globalIndexForTopicStart / topicIndexForGlobal)', () {
    test('single topic: all offsets are 0 and every global maps back to 0', () {
      const counts = [5];
      expect(globalIndexForTopicStart(counts, 0), 0);
      expect(globalIndexForTopicStart(counts, 99), 0); // out-of-range guard
      for (int g = 0; g < 5; g++) {
        expect(topicIndexForGlobal(counts, g), 0);
      }
    });

    test('multi-topic: first-question offsets are correct', () {
      // topics: [3, 4, 2, 6] => first global indices 0, 3, 7, 9
      const counts = [3, 4, 2, 6];
      expect(globalIndexForTopicStart(counts, 0), 0);
      expect(globalIndexForTopicStart(counts, 1), 3);
      expect(globalIndexForTopicStart(counts, 2), 7);
      expect(globalIndexForTopicStart(counts, 3), 9);
    });

    test('multi-topic: global-to-topic mapping is correct at every boundary', () {
      // topics: [3, 4, 2, 6] => total 15 questions
      // boundaries: [0..2]→0, [3..6]→1, [7..8]→2, [9..14]→3
      const counts = [3, 4, 2, 6];

      // Spot-check first and last index of each topic
      expect(topicIndexForGlobal(counts, 0), 0);
      expect(topicIndexForGlobal(counts, 2), 0);
      expect(topicIndexForGlobal(counts, 3), 1);
      expect(topicIndexForGlobal(counts, 6), 1);
      expect(topicIndexForGlobal(counts, 7), 2);
      expect(topicIndexForGlobal(counts, 8), 2);
      expect(topicIndexForGlobal(counts, 9), 3);
      expect(topicIndexForGlobal(counts, 14), 3);
    });

    test('globalIndexForTopicStart round-trips with topicIndexForGlobal', () {
      // For any topic t, the global start of t should map back to t.
      const counts = [3, 4, 2, 6];
      for (int t = 0; t < counts.length; t++) {
        final g = globalIndexForTopicStart(counts, t);
        expect(topicIndexForGlobal(counts, g), t,
            reason: 'topic $t → global $g should round-trip back to $t');
      }
    });

    test('out-of-range globalIndex returns last topic, never crashes', () {
      const counts = [3, 4, 2, 6];
      expect(topicIndexForGlobal(counts, 9999), counts.length - 1);
    });
  });
}
