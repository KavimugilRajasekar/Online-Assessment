import 'choice.dart';

enum QuestionType { mcqSingle, mcqMulti, codeMcq, coding, unknown }

QuestionType parseQType(String s) {
  switch (s) {
    case 'mcq_single': return QuestionType.mcqSingle;
    case 'mcq_multi': return QuestionType.mcqMulti;
    case 'code_mcq': return QuestionType.codeMcq;
    case 'coding': return QuestionType.coding;
    default: return QuestionType.unknown;
  }
}

class Question {
  final String id;
  final QuestionType qtype;
  final String text;
  final String code;
  final double marks;
  final List<Choice> choices;
  final String starterCode;
  final String language;
  final String explanation;
  final String topicId;
  final String topicName;

  const Question({
    required this.id,
    required this.qtype,
    required this.text,
    required this.code,
    required this.marks,
    required this.choices,
    required this.starterCode,
    required this.language,
    required this.explanation,
    this.topicId = '',
    this.topicName = '',
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: (json['id'] ?? '').toString(),
        qtype: parseQType((json['qtype'] ?? '').toString()),
        text: (json['text'] ?? '').toString(),
        code: (json['code'] ?? '').toString(),
        marks: ((json['marks']) as num? ?? 0).toDouble(),
        choices: ((json['choices'] as List?) ?? [])
            .map((c) => Choice.fromJson(
                c is Map<String, dynamic>
                    ? c
                    : (c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{})))
            .toList(),
        starterCode: (json['starter_code'] ?? '').toString(),
        language: (json['language'] ?? '').toString(),
        explanation: (json['explanation'] ?? '').toString(),
        topicId: (json['topic_id'] ?? '').toString(),
        topicName: (json['topic_name'] ?? '').toString(),
      );
}
