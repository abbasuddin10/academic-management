import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralised session handling.
///
/// Only auth-related preference keys are removed on sign-out so unrelated app
/// settings (device id, ad tracking counters, ...) are preserved.
class SessionService {
  const SessionService._();

  static const String studentLoggedInKey = 'is_student_logged_in';
  static const String teacherLoggedInKey = 'is_teacher_logged_in';
  static const String studentNameKey = 'student_name';
  static const String studentAcademyKey = 'student_academy';
  static const String studentClassKey = 'student_class';
  static const String studentRollKey = 'student_roll';
  static const String studentAcademyIdKey = 'student_academy_id';
  static const String studentIdKey = 'student_id';
  static const String teacherEmailKey = 'teacher_email';
  static const String teacherIdKey = 'teacher_id';
  static const String academyIdKey = 'academy_id';

  static const List<String> authKeys = <String>[
    studentLoggedInKey,
    teacherLoggedInKey,
    studentNameKey,
    studentAcademyKey,
    studentClassKey,
    studentRollKey,
    studentAcademyIdKey,
    studentIdKey,
    teacherEmailKey,
    teacherIdKey,
    academyIdKey,
  ];

  /// Signs the user out of Supabase (if a session exists) and removes only the
  /// auth-related local preferences.
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in authKeys) {
      await prefs.remove(key);
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // A missing/expired session is already a signed-out state.
    }

    if (Get.isRegistered<AppStateController>()) {
      Get.find<AppStateController>().clearSession();
    }
  }

  /// Fetches the authoritative `users` row for an email address through the
  /// narrowly scoped SECURITY DEFINER RPC (see migration 0001).
  static Future<Map<String, dynamic>?> fetchUserRow(String email) async {
    if (email.trim().isEmpty) return null;
    try {
      final result = await Supabase.instance.client.rpc(
        'lookup_login_user',
        params: {'p_email': email.trim()},
      );
      if (result is List && result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Opens (or reuses) a Supabase anonymous session for teacher/student users
  /// and registers their tenant so RLS policies can scope their queries.
  /// Failures are non-fatal: legacy anon reads remain available as a fallback.
  static Future<bool> startAppSession({
    required String academyId,
    required String role,
    String? displayName,
    String? readerKey,
  }) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.isAnonymous != true) {
        await client.auth.signInAnonymously();
      }
      await client.rpc('upsert_app_session', params: {
        'p_academy_id': academyId,
        'p_role': role,
        'p_display_name': displayName,
      });

      // Persist the reader key so the database can enforce RLS on notice_reads.
      if (readerKey != null && readerKey.isNotEmpty) {
        try {
          await client.rpc('set_app_session_reader_key', params: {
            'p_reader_key': readerKey,
          });
        } catch (e) {
          // Legacy backend: reads still work, but RLS cannot verify the key.
          debugPrint('Reader key registration skipped: $e');
        }
      }

      if (Get.isRegistered<AppStateController>()) {
        Get.find<AppStateController>().setSession(
          academyId: academyId,
          role: role,
          readerKey: readerKey,
        );
      }
      return true;
    } catch (e) {
      debugPrint('Anonymous app session unavailable: $e');
      return false;
    }
  }

  /// Re-asserts the anonymous session's tenant + reader key before an FCM
  /// token is written to `student_devices`. The RLS insert policy on that
  /// table checks `student_id = split_part(current_reader_key(), ':', 2)`;
  /// if the reader key was never persisted (older installs, expired session,
  /// or a failed login RPC) the upsert is silently rejected and the Edge
  /// Function later reports "no device tokens". Both RPCs are idempotent.
  static Future<void> ensureReaderKey({
    required String academyId,
    required String role,
    required String readerKey,
    String? displayName,
  }) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null || readerKey.isEmpty) return;
      await client.rpc('upsert_app_session', params: {
        'p_academy_id': academyId,
        'p_role': role,
        'p_display_name': displayName,
      });
      await client.rpc('set_app_session_reader_key', params: {
        'p_reader_key': readerKey,
      });
    } catch (e) {
      // Legacy backend or transient failure: token sync still proceeds.
      debugPrint('Reader key re-assert skipped: $e');
    }
  }

  /// Stable per-recipient key: `auth.uid()` for admins, otherwise
  /// `teacher:<id>` / `student:<id>`.
  static String readerKeyFor({
    required String role,
    required String userId,
  }) {
    if (role == 'student') return 'student:$userId';
    if (isTeacherRole(role)) return 'teacher:$userId';
    return userId;
  }

  /// Resolves everything the read-tracking/realtime layer needs from the
  /// authoritative local session plus Supabase auth.
  static Future<NoticeContext> noticeContext() async {
    final prefs = await SharedPreferences.getInstance();
    final isStudent =
        prefs.getBool(studentLoggedInKey) ?? false;
    final isTeacher =
        prefs.getBool(teacherLoggedInKey) ?? false;
    final client = Supabase.instance.client;

    String academyId;
    String role;
    String userId;
    String className = '';

    if (isStudent) {
      role = 'student';
      academyId = prefs.getString(studentAcademyIdKey) ?? '';
      userId = prefs.getString(studentIdKey) ?? '';
      className = prefs.getString(studentClassKey) ?? '';
    } else if (isTeacher) {
      role = 'teacher';
      academyId = prefs.getString(academyIdKey) ?? '';
      userId = prefs.getString(teacherIdKey) ?? '';
    } else {
      role = 'super_admin';
      userId = client.auth.currentUser?.id ?? '';
      academyId = prefs.getString(academyIdKey) ?? '';
      if ((userId.isEmpty || academyId.isEmpty) &&
          client.auth.currentUser?.email != null) {
        final row = await fetchUserRow(client.auth.currentUser!.email!);
        if (userId.isEmpty) userId = row?['id']?.toString() ?? '';
        if (academyId.isEmpty) {
          academyId = row?['academy_id']?.toString() ?? '';
        }
      }
    }

    // Final tenant fallback: the controller is populated at every login.
    if (academyId.isEmpty && Get.isRegistered<AppStateController>()) {
      academyId = Get.find<AppStateController>().academyId.value ?? '';
    }

    return NoticeContext(
      academyId: academyId,
      role: role,
      readerKey: readerKeyFor(role: role, userId: userId),
      className: className,
      studentId: isStudent ? userId : '',
      studentName: isStudent
          ? (prefs.getString(studentNameKey) ?? '')
          : '',
      studentRoll: isStudent ? (prefs.getString(studentRollKey) ?? '') : '',
      studentAcademyName: isStudent
          ? (prefs.getString(studentAcademyKey) ?? '')
          : '',
    );
  }

  /// Reads the tenant/role recorded for the current anonymous session.
  static Future<Map<String, dynamic>?> fetchAppSession() async {
    try {
      final result = await Supabase.instance.client.rpc('get_app_session');
      if (result is List && result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Validates that a cached student record still exists in the database.
  static Future<bool> studentRecordIsValid({
    required String studentId,
    required String academyId,
    required String className,
    required String roll,
  }) async {
    if (studentId.isEmpty || academyId.isEmpty) return false;
    try {
      final row = await Supabase.instance.client
          .from('students')
          .select('id')
          .eq('id', studentId)
          .eq('academy_id', academyId)
          .eq('class', className)
          .eq('roll', roll)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  /// Returns true when [role] is one of the roles that use the teacher home
  /// screen.
  static bool isTeacherRole(String? role) =>
      role == 'teacher' || role == 'staff';
}

/// Everything needed to scope notice reads and unread counts to one recipient.
class NoticeContext {
  final String academyId;
  final String role;
  final String readerKey;
  final String className;
  final String studentId;
  final String studentName;
  final String studentRoll;
  final String studentAcademyName;

  const NoticeContext({
    required this.academyId,
    required this.role,
    required this.readerKey,
    this.className = '',
    this.studentId = '',
    this.studentName = '',
    this.studentRoll = '',
    this.studentAcademyName = '',
  });
}
