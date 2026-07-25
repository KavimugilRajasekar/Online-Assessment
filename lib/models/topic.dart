import 'subtopic.dart';

class Topic {
  final String id;
  final String name;
  final List<Subtopic> subtopics;
  final int questionCount;

  const Topic({
    required this.id,
    required this.name,
    required this.subtopics,
    required this.questionCount,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] as String,
        name: json['name'] as String,
        subtopics: ((json['subtopics'] as List?) ?? [])
            .map((s) => Subtopic.fromJson(s as Map<String, dynamic>))
            .toList(),
        questionCount: (json['question_count'] as int?) ?? 0,
      );
}
