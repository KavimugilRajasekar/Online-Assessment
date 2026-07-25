import 'question.dart';
import 'answer.dart';

class AnswerResult {
  final Question question;
  final Answer answer;

  const AnswerResult({required this.question, required this.answer});

  factory AnswerResult.fromJson(Map<String, dynamic> json) {
    final answerJson = json['answer'] is Map<String, dynamic>
        ? json['answer'] as Map<String, dynamic>
        : (json['answer'] is Map
            ? Map<String, dynamic>.from(json['answer'] as Map)
            : json);
    final questionJson = json['question'] is Map<String, dynamic>
        ? json['question'] as Map<String, dynamic>
        : (json['question'] is Map
            ? Map<String, dynamic>.from(json['question'] as Map)
            : <String, dynamic>{});

    return AnswerResult(
      question: Question.fromJson(questionJson),
      answer: Answer.fromJson(answerJson),
    );
  }
}

class QuizResult {
  final String id;
  final String quizId;
  final String status;
  final double totalMarks;
  final double score;
  final String? submittedAt;
  final List<AnswerResult> answers;

  const QuizResult({
    required this.id,
    required this.quizId,
    required this.status,
    required this.totalMarks,
    required this.score,
    this.submittedAt,
    required this.answers,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
        id: (json['id'] ?? '').toString(),
        quizId: (json['quiz_id'] ?? json['quiz'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        totalMarks: ((json['total_marks']) as num? ?? 0).toDouble(),
        score: ((json['score']) as num? ?? 0).toDouble(),
        submittedAt: json['submitted_at']?.toString(),
        answers: ((json['answers'] as List?) ?? [])
            .map((a) => AnswerResult.fromJson(
                a is Map<String, dynamic>
                    ? a
                    : (a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{})))
            .toList(),
      );
}
