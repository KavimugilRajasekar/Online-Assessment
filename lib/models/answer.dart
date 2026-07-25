class Answer {
  final String questionId;
  final List<String> selectedChoiceIds;
  final String codeText;
  final bool? isCorrect;
  final double marksAwarded;

  const Answer({
    required this.questionId,
    required this.selectedChoiceIds,
    required this.codeText,
    this.isCorrect,
    required this.marksAwarded,
  });

  factory Answer.fromJson(Map<String, dynamic> json) {
    final qIdRaw = json['question_id'] ?? json['question'];
    final String qId = qIdRaw is String
        ? qIdRaw
        : (qIdRaw is Map ? (qIdRaw['id']?.toString() ?? '') : '');
    return Answer(
      questionId: qId,
      selectedChoiceIds: ((json['selected_choice_ids'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      codeText: (json['code_text'] as String?) ?? '',
      isCorrect: json['is_correct'] as bool?,
      marksAwarded: ((json['marks_awarded']) as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        'selected_choice_ids': selectedChoiceIds,
        'code_text': codeText,
      };
}
