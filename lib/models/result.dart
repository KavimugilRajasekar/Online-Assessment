import 'question.dart';
import 'answer.dart';

class AnswerResult {
  final Question question;
  final Answer answer;

  const AnswerResult({required this.question, required this.answer});

  factory AnswerResult.fromJson(Map<String, dynamic> json) => AnswerResult(
        question: Question.fromJson(json['question'] as Map<String, dynamic>),
        answer: Answer.fromJson(json),
      );
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
        id: json['id'] as String,
        quizId: (json['quiz_id'] ?? '') as String,
        status: (json['status'] as String?) ?? '',
        totalMarks: ((json['total_marks']) as num? ?? 0).toDouble(),
        score: ((json['score']) as num? ?? 0).toDouble(),
        submittedAt: json['submitted_at'] as String?,
        answers: ((json['answers'] as List?) ?? [])
            .map((a) => AnswerResult.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}
