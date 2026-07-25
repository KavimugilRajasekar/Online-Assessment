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
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        qtype: parseQType(json['qtype'] as String),
        text: json['text'] as String,
        code: (json['code'] as String?) ?? '',
        marks: ((json['marks']) as num).toDouble(),
        choices: ((json['choices'] as List?) ?? [])
            .map((c) => Choice.fromJson(c as Map<String, dynamic>))
            .toList(),
        starterCode: (json['starter_code'] as String?) ?? '',
        language: (json['language'] as String?) ?? '',
        explanation: (json['explanation'] as String?) ?? '',
      );
}
