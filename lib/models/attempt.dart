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

  /// Safely parses [s] as a UTC [DateTime].
  /// Handles empty strings, missing 'Z' suffix, and space-separated formats.
  static DateTime _parseDate(String s) {
    if (s.isEmpty) return DateTime.now().toUtc();
    // Normalise: replace space separator with 'T' and ensure 'Z' suffix.
    String normalised = s.trim().replaceFirst(' ', 'T');
    if (!normalised.endsWith('Z') && !normalised.contains('+') && !RegExp(r'-\d{2}:\d{2}$').hasMatch(normalised)) {
      normalised += 'Z';
    }
    return DateTime.tryParse(normalised)?.toUtc() ?? DateTime.now().toUtc();
  }

  DateTime get deadlineDateTime => _parseDate(deadlineAt);
  DateTime get startedAtDateTime => _parseDate(startedAt);
}
