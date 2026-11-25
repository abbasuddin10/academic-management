import 'package:academy_management/models/academy.dart';
import 'base_repository.dart';

class AcademyRepository extends BaseRepository {
  Future<List<Academy>> fetchAll() async {
    final rows = await client
        .from('academies')
        .select('id, academy_name, address, logo_url');
    return (rows as List)
        .map((row) => Academy.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Academy?> fetchById(String academyId) async {
    if (academyId.isEmpty) return null;
    final row = await client
        .from('academies')
        .select()
        .eq('id', academyId)
        .maybeSingle();
    if (row == null) return null;
    return Academy.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Resolves the tenant of the signed-in Supabase Auth user from the
  /// authoritative `users` table.
  Future<String?> currentUserAcademyId() async {
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) return null;
    try {
      final rows = await client
          .from('users')
          .select('academy_id')
          .eq('email', email)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return rows.first['academy_id']?.toString();
    } catch (_) {
      return null;
    }
  }
}
