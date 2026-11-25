import 'dart:async';
import 'dart:convert';

import 'package:academy_management/models/app_notification.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/finance/teacher_salary_page.dart';
import 'package:academy_management/views/notices/notice_board_view.dart';
import 'package:academy_management/views/student/student_home_view.dart';
import 'package:academy_management/views/student/student_notification_center_view.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parsed representation of an FCM/local-notification payload.
class NotificationPayload {
  final String type;
  final String id;
  final String route;
  final String academyId;

  /// `app_notifications.id` from data-only pushes. `id` above stays the event
  /// target (student/teacher/history id) used for navigation.
  final String notificationId;

  const NotificationPayload({
    required this.type,
    required this.id,
    required this.route,
    required this.academyId,
    this.notificationId = '',
  });

  bool get isNotice => type == NotificationTypes.notice || type.isEmpty;
}

/// Turns notification payloads into real navigation (legacy + event payloads).
class NotificationRouter {
  const NotificationRouter._();

  /// Backward-compatible entry point used by existing deep links.
  static Future<void> handleNotice(String? payload) => handlePayload(payload);

  static Future<void> handlePayload(String? payload) async {
    final parsed = parsePayload(payload);
    if (parsed == null) return;

    final context = await SessionService.noticeContext();
    if (context.academyId.isEmpty) {
      debugPrint('Notification tap ignored: no academy context');
      return;
    }

    // Optional, frequency-capped interstitial on notification taps. This is
    // strictly best-effort: the helper returns immediately (and never throws)
    // when no ad is cached, the 30-minute cooldown is active, or the daily cap
    // is reached — so the navigation below is never blocked.
    await AdService.showNotificationTapAd();

    if (parsed.isNotice || context.role == 'super_admin') {
      await Get.to(
        () => NoticeBoardView(
          academyId: context.academyId,
          userRole: context.role,
        ),
      );
      return;
    }

    // Teacher/staff share the same unified inbox pattern as students, so a
    // salary push opens the item instead of a notice-only board.
    if (SessionService.isTeacherRole(context.role)) {
      await _openTeacherCenter(context);
      return;
    }

    // Academic/fee events: open the student dashboard on the matching tab.
    // Passing the route down keeps navigation argument-safe (fallbacks live in
    // StudentHomeView) and works even when the app was terminated.
    await Get.offAll(
      () => StudentHomeView(
        studentName: context.studentName,
        academyName: context.studentAcademyName,
        className: context.className,
        roll: context.studentRoll,
        initialNotificationRoute: parsed.route,
        initialTargetId: parsed.id,
      ),
    );
  }

  static Future<void> _openTeacherCenter(NoticeContext context) async {
    List<Notice> notices = <Notice>[];
    try {
      notices = await NoticeRepository().fetch(
        context.academyId,
        readerKey: context.readerKey,
        role: context.role,
        className: context.className,
      );
    } catch (_) {
      // An offline notice fetch must not block the salary notification.
    }

    await Get.to(
      () => StudentNotificationCenterView(
        academyId: context.academyId,
        readerKey: context.readerKey,
        className: context.className,
        notices: notices,
        onOpen: (route, _) => _openTeacherTarget(context, route),
      ),
    );
  }

  static void _openTeacherTarget(NoticeContext context, String route) {
    if (route == 'teacher_salary' || route == 'fee') {
      unawaited(_openTeacherSalaryPage(context));
      return;
    }
    unawaited(
      Get.to(
        () => NoticeBoardView(
          academyId: context.academyId,
          userRole: context.role,
        ),
      ),
    );
  }

  static Future<void> _openTeacherSalaryPage(NoticeContext context) async {
    final teacherId = context.readerKey.startsWith('teacher:')
        ? context.readerKey.substring('teacher:'.length)
        : '';
    if (teacherId.isEmpty) {
      await Get.to(
        () => NoticeBoardView(
          academyId: context.academyId,
          userRole: context.role,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(SessionService.teacherEmailKey) ?? '';
    final userRow = email.isEmpty
        ? null
        : await SessionService.fetchUserRow(email);
    final teacherName = userRow?['full_name']?.toString() ?? 'শিক্ষক';

    await Get.to(
      () => TeacherSalaryPageView(
        academyId: context.academyId,
        teacherEmail: email,
        teacherName: teacherName,
        teacherId: teacherId,
      ),
    );
  }

  /// Accepts:
  ///   * JSON: {"type":"fee","route":"fee","target_id":"...", ...}
  ///   * legacy JSON: {"notice_id":"..."}
  ///   * bare id / `notice_id=123` / `123|academy-id`
  static NotificationPayload? parsePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final value = payload.trim();

    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        final id =
            (decoded['target_id'] ?? decoded['notice_id'] ?? decoded['id'])
                ?.toString() ??
            '';
        final type =
            decoded['type']?.toString() ??
            (decoded.containsKey('notice_id') ? NotificationTypes.notice : '');
        final route = decoded['route']?.toString() ?? type;
        return NotificationPayload(
          type: type,
          id: id,
          route: route,
          academyId: decoded['academy_id']?.toString() ?? '',
          notificationId: decoded['notification_id']?.toString() ?? '',
        );
      } catch (_) {
        return null;
      }
    }

    final firstPart = value.split('|').first;
    final id = firstPart.contains('=') ? firstPart.split('=').last : firstPart;
    return NotificationPayload(
      type: NotificationTypes.notice,
      id: id,
      route: NotificationTypes.notice,
      academyId: value.split('|').length > 1 ? value.split('|').last : '',
    );
  }

  static String? parseNoticeId(String? payload) => parsePayload(payload)?.id;
}
