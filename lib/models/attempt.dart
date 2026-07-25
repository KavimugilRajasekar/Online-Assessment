import 'question.dart';

enum AttemptStatus { inProgress, submitted, expired, unknown }

AttemptStatus parseStatus(String s) {
  switch (s) {
    case 'in_progress': return AttemptStatus.inProgress;
    case 'submitted': return AttemptStatus.submitted;
    case 'expired': return AttemptStatus.expired;
    default: return AttemptStatus.unknown;
  }
}

class Attempt {
  final String id;
  final String quizId;
  final AttemptStatus status;
  final String startedAt;
  final String deadlineAt;
  final double totalMarks;
  final List<String> questionOrder;
  final List<Question> questions;

  const Attempt({
    required this.id,
    required this.quizId,
    required this.status,
    required this.startedAt,
    required this.deadlineAt,
    required this.totalMarks,
    required this.questionOrder,
    required this.questions,
  });

  factory Attempt.fromJson(Map<String, dynamic> json) => Attempt(
        id: json['id'] as String,
        quizId: (json['quiz_id'] ?? json['quiz'] ?? '') as String,
        status: parseStatus((json['status'] as String?) ?? ''),
        startedAt: (json['started_at'] as String?) ?? '',
        deadlineAt: (json['deadline_at'] as String?) ?? '',
        totalMarks: ((json['total_marks']) as num? ?? 0).toDouble(),
        questionOrder: ((json['question_order'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        questions: ((json['questions'] as List?) ?? [])
            .map((q) => Question.fromJson(q as Map<String, dynamic>))
            .toList(),
      );

  DateTime get deadlineDateTime => DateTime.parse(deadlineAt);
}
