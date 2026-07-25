class Subtopic {
  final String id;
  final String name;
  final int questionCount;

  const Subtopic({
    required this.id,
    required this.name,
    required this.questionCount,
  });

  factory Subtopic.fromJson(Map<String, dynamic> json) => Subtopic(
        id: json['id'] as String,
        name: json['name'] as String,
        questionCount: (json['question_count'] as int?) ?? 0,
      );
}
