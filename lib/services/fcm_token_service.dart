import 'package:academy_management/repositories/notification_repository.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the signed-in recipient's FCM token where the shared Edge Function
/// expects it: `student_devices` for students and `users.fcm_token` for
/// teachers, staff and admins.
class FcmTokenService {
  const FcmTokenService._();

  static String? _lastToken;

  /// Call after a successful session is established (login and app restore).
  static Future<void> syncNow() async {
    try {
      final context = await SessionService.noticeContext();
      if (context.academyId.isEmpty || context.readerKey.isEmpty) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _lastToken = token;

      // Guarantee the RLS precondition for token writes before upserting.
      await SessionService.ensureReaderKey(
        academyId: context.academyId,
        role: context.role,
        readerKey: context.readerKey,
        displayName: context.studentName,
      );

      if (context.role == 'student') {
        final studentId = context.readerKey.substring('student:'.length);
        if (studentId.isEmpty) return;

        await NotificationRepository().registerDeviceToken(
          academyId: context.academyId,
          studentId: studentId,
          token: token,
          platform: defaultTargetPlatform.name,
        );

        // Keep the legacy column in sync for older admin tooling.
        try {
          await Supabase.instance.client
              .from('students')
              .update({'fcm_token': token})
              .eq('id', studentId);
        } catch (_) {}
        return;
      }

      // Teachers/staff/admins are addressed through users.fcm_token, which the
      // send-push Edge Function resolves for their reader key.
      if (SessionService.isTeacherRole(context.role) ||
          context.role == 'super_admin') {
        final userId = context.readerKey.startsWith('teacher:')
            ? context.readerKey.substring('teacher:'.length)
            : context.readerKey;
        if (userId.isEmpty) return;
        await Supabase.instance.client
            .from('users')
            .update({'fcm_token': token})
            .eq('id', userId);
      }
    } catch (e) {
      debugPrint('FCM token sync skipped: $e');
    }
  }

  /// Fires whenever FCM rotates the token; call once at startup.
  static void listenForRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (token.isEmpty || token == _lastToken) return;
      _lastToken = token;
      syncNow();
    });
  }
}
