/// Data model for a question stored in `academy_questions`.
class Question {
  final Map<String, dynamic> raw;

  const Question(this.raw);

  factory Question.fromMap(Map<String, dynamic> map) => Question(
        Map<String, dynamic>.from(map),
      );

  String get id => raw['id']?.toString() ?? '';
  String get text =>
      (raw['question'] ?? raw['question_text'] ?? '').toString();
  String get chapter => raw['chapter_name']?.toString() ?? '';
  String get className => raw['class_name']?.toString() ?? '';
  String get subject => raw['subject_name']?.toString() ?? '';

  Map<String, dynamic> toMap() => raw;
}
