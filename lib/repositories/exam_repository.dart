import 'package:academy_management/models/question.dart';
import 'base_repository.dart';

/// Data access for question banks and exam schedules.
class ExamRepository extends BaseRepository {
  Future<List<Question>> fetchQuestions({
    required String academyId,
    required String className,
    required String subjectName,
    required String chapterName,
  }) async {
    final rows = await client
        .from('academy_questions')
        .select()
        .eq('academy_id', academyId)
        .eq('class_name', className)
        .eq('subject_name', subjectName)
        .eq('chapter_name', chapterName);
    return (rows as List)
        .map((row) => Question.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> deleteSchedule(String examId, String academyId) async {
    if (academyId.isEmpty) {
      throw ArgumentError.value(academyId, 'academyId', 'must not be empty');
    }
    await client
        .from('exam_schedules')
        .delete()
        .eq('id', examId)
        .eq('academy_id', academyId);
  }
}
