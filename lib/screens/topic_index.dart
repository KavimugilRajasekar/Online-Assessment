/// Pure-math helpers for translating between per-topic question offsets
/// and global (flattened) question indices. Kept top-level so they can be
/// unit-tested without instantiating the QuizScreen widget tree.
library;

/// Number of questions in each topic, in topic order.
typedef TopicQuestionCounts = List<int>;

/// The global (flattened) index of the first question in the topic at
/// [topicIndex]. Returns 0 for the first topic, and 0 for an out-of-range
/// index so callers can use the value directly in [_pageController.jumpToPage]
/// without crashing on a race with a mid-rebuild topic list.
int globalIndexForTopicStart(TopicQuestionCounts topicCounts, int topicIndex) {
  if (topicIndex <= 0) return 0;
  if (topicIndex >= topicCounts.length) return 0;
  int offset = 0;
  for (int i = 0; i < topicIndex; i++) {
    offset += topicCounts[i];
  }
  return offset;
}

/// The topic index that contains the global question at [globalIndex].
/// If [globalIndex] is past the end, returns the last valid topic.
int topicIndexForGlobal(TopicQuestionCounts topicCounts, int globalIndex) {
  if (topicCounts.isEmpty) return 0;
  int offset = 0;
  for (int i = 0; i < topicCounts.length; i++) {
    offset += topicCounts[i];
    if (globalIndex < offset) return i;
  }
  return topicCounts.length - 1;
}
