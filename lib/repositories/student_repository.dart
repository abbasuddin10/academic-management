import 'package:academy_management/models/student.dart';
import 'base_repository.dart';

class StudentRepository extends BaseRepository {
  Future<List<Student>> fetchByAcademy(String academyId) async {
    final rows = await client
        .from('students')
        .select()
        .eq('academy_id', academyId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => Student.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<String>> classesForAcademy(String academyId) async {
    final rows = await client
        .from('students')
        .select('class')
        .eq('academy_id', academyId);
    return (rows as List)
        .map((row) => row['class']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> delete(String studentId, String academyId) async {
    if (academyId.isEmpty) {
      throw ArgumentError.value(academyId, 'academyId', 'must not be empty');
    }
    await client
        .from('students')
        .delete()
        .eq('id', studentId)
        .eq('academy_id', academyId);
  }

  /// Updates the cached student password to a hashed value (legacy upgrade).
  Future<void> updatePasswordHash(String studentId, String hash) async {
    await client
        .from('students')
        .update({'custom_password': hash})
        .eq('id', studentId);
  }
}
