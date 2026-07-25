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

  factory Answer.fromJson(Map<String, dynamic> json) => Answer(
        questionId: (json['question_id'] ?? json['question'] ?? '') as String,
        selectedChoiceIds: ((json['selected_choice_ids'] as List?) ?? [])
            .map((e) => e as String)
            .toList(),
        codeText: (json['code_text'] as String?) ?? '',
        isCorrect: json['is_correct'] as bool?,
        marksAwarded: ((json['marks_awarded']) as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        'selected_choice_ids': selectedChoiceIds,
        'code_text': codeText,
      };
}
