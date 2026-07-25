class Choice {
  final String id;
  final String text;
  final bool? isCorrect; // null in public view; populated in results

  const Choice({required this.id, required this.text, this.isCorrect});

  factory Choice.fromJson(Map<String, dynamic> json) => Choice(
        id: json['id'] as String,
        text: json['text'] as String,
        isCorrect: json['is_correct'] as bool?,
      );
}
