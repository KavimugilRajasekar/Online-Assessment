class Quiz {
  final String id;
  final String title;
  final String description;
  final int durationSeconds;
  final bool shuffleQuestions;
  final bool shuffleChoices;
  final int topicCount;

  final bool answersPosted;

  const Quiz({
    required this.id,
    required this.title,
    required this.description,
    required this.durationSeconds,
    required this.shuffleQuestions,
    required this.shuffleChoices,
    required this.topicCount,
    this.answersPosted = false,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) => Quiz(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        durationSeconds: json['duration_seconds'] as int,
        shuffleQuestions: (json['shuffle_questions'] as bool?) ?? true,
        shuffleChoices: (json['shuffle_choices'] as bool?) ?? true,
        topicCount: (json['topic_count'] as int?) ?? 0,
        answersPosted: (json['answers_posted'] as bool?) ?? false,
      );
}
