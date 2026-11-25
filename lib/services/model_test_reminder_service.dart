import 'dart:convert';

import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/notification_service.dart';
import 'package:academy_management/services/notification_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A persisted reminder for one scheduled model test.
class TestReminder {
  final String academyId;
  final String studentId;
  final String testId;
  final String testTitle;
  final DateTime startAt;
  final int minutesBefore;
  final bool scheduled;
  final DateTime? lastShownAt;

  const TestReminder({
    required this.academyId,
    required this.studentId,
    required this.testId,
    required this.testTitle,
    required this.startAt,
    required this.minutesBefore,
    required this.scheduled,
    this.lastShownAt,
  });

  DateTime get fireAt => startAt.subtract(Duration(minutes: minutesBefore));

  bool get isPast =>
      startAt.isBefore(DateTime.now().subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
    'academyId': academyId,
    'studentId': studentId,
    'testId': testId,
    'testTitle': testTitle,
    'startAt': startAt.toIso8601String(),
    'minutesBefore': minutesBefore,
    'scheduled': scheduled,
    'lastShownAt': lastShownAt?.toIso8601String(),
  };

  factory TestReminder.fromJson(Map<String, dynamic> map) => TestReminder(
    academyId: map['academyId']?.toString() ?? '',
    studentId: map['studentId']?.toString() ?? '',
    testId: map['testId']?.toString() ?? '',
    testTitle: map['testTitle']?.toString() ?? '',
    startAt:
        DateTime.tryParse(map['startAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    minutesBefore: int.tryParse(map['minutesBefore']?.toString() ?? '') ?? 30,
    scheduled: map['scheduled'] == true,
    lastShownAt: DateTime.tryParse(map['lastShownAt']?.toString() ?? ''),
  );

  TestReminder copyWith({
    int? minutesBefore,
    bool? scheduled,
    DateTime? lastShownAt,
    bool clearLastShownAt = false,
  }) => TestReminder(
    academyId: academyId,
    studentId: studentId,
    testId: testId,
    testTitle: testTitle,
    startAt: startAt,
    minutesBefore: minutesBefore ?? this.minutesBefore,
    scheduled: scheduled ?? this.scheduled,
    lastShownAt: clearLastShownAt ? null : lastShownAt ?? this.lastShownAt,
  );
}

/// Outcome of a reminder change, used for clear user feedback.
class ReminderResult {
  final bool saved;
  final bool scheduled;
  final String message;

  const ReminderResult({
    required this.saved,
    required this.scheduled,
    required this.message,
  });
}

/// Persists model-test reminders and schedules real local notifications when
/// the platform allows it. When scheduling is unavailable the reminder is
/// still saved and surfaced inside the app, never silently lost.
class ModelTestReminderService {
  ModelTestReminderService._();

  static const _prefsKey = 'model_test_reminders_v1';
  static const _channelId = 'model_test_reminders';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(AppNotificationStyle.smallIcon),
      ),
      onDidReceiveNotificationResponse: (response) {
        // Reuse the existing deep-link router (push routing stays untouched).
        NotificationService.handleTap(response.payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(AppNotificationStyle.reminderChannel);
    _initialized = true;
  }

  static int _notificationId(String testId) =>
      1000 + (testId.hashCode.abs() % 100000000);

  /// Resolves the signed-in student's institute logo for the right-side
  /// notification avatar. Never fails: the generic drawable is always there.
  static Future<AndroidBitmap<Object>> _instituteLargeIcon(
    String academyId,
  ) async {
    final id = academyId.trim();
    if (id.isEmpty) return AppNotificationStyle.fallbackLargeIcon;
    try {
      final academy = await AcademyRepository().fetchById(id);
      return await AppNotificationStyle.largeIconFromUrl(academy?.logoUrl);
    } catch (e) {
      debugPrint('Reminder institute logo lookup skipped: $e');
      return AppNotificationStyle.fallbackLargeIcon;
    }
  }

  static Future<List<TestReminder>> load({
    required String academyId,
    required String studentId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <TestReminder>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TestReminder>[];

      final reminders = <TestReminder>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final reminder = TestReminder.fromJson(Map<String, dynamic>.from(item));
        if (reminder.academyId == academyId &&
            reminder.studentId == studentId &&
            !reminder.isPast) {
          reminders.add(reminder);
        }
      }
      reminders.sort((a, b) => a.startAt.compareTo(b.startAt));

      // Drop expired entries globally so the list cannot grow forever.
      final all = await _readAll()
        ..removeWhere((item) => item.isPast);
      await _save(all, scopeAcademyId: null);
      return reminders;
    } catch (e) {
      debugPrint('Reminder load failed: $e');
      return <TestReminder>[];
    }
  }

  static Future<void> _save(
    List<TestReminder> reminders, {
    required String? scopeAcademyId,
    String? scopeStudentId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<TestReminder> kept = reminders;
      if (scopeAcademyId != null) {
        final stored = await _readAll();
        kept =
            stored
                .where(
                  (item) =>
                      item.academyId != scopeAcademyId ||
                      (scopeStudentId != null &&
                          item.studentId != scopeStudentId),
                )
                .toList()
              ..addAll(reminders);
      }
      await prefs.setString(
        _prefsKey,
        jsonEncode(kept.map((item) => item.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Reminder persist failed: $e');
    }
  }

  static Future<List<TestReminder>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <TestReminder>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TestReminder>[];
      return decoded
          .whereType<Map>()
          .map((item) => TestReminder.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <TestReminder>[];
    }
  }

  static Future<ReminderResult> set({
    required String academyId,
    required String studentId,
    required String testId,
    required String testTitle,
    required DateTime startAt,
    required int minutesBefore,
  }) async {
    if (!startAt.isAfter(DateTime.now())) {
      return const ReminderResult(
        saved: false,
        scheduled: false,
        message: 'এই পরীক্ষাটি শুরু হয়ে গেছে।',
      );
    }
    final fireAt = startAt.subtract(Duration(minutes: minutesBefore));
    final reminder = TestReminder(
      academyId: academyId,
      studentId: studentId,
      testId: testId,
      testTitle: testTitle,
      startAt: startAt.toLocal(),
      minutesBefore: minutesBefore,
      scheduled: false,
    );

    var scheduled = false;
    String detail;
    try {
      await _ensureInitialized();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final permission =
          await android?.requestNotificationsPermission() ?? true;
      if (!permission) {
        detail = 'বিজ্ঞপ্তির অনুমতি না থাকায় শুধু অ্যাপের ভেতরে দেখানো হবে।';
      } else {
        final title = 'আসন্ন মডেল টেস্ট: $testTitle';
        final body = '${_format(startAt)} থেকে পরীক্ষা শুরু হবে।';
        final largeIcon = await _instituteLargeIcon(academyId);
        final details = NotificationDetails(
          android: AppNotificationStyle.details(
            channelId: _channelId,
            channelName: AppNotificationStyle.reminderChannel.name,
            channelDescription:
                AppNotificationStyle.reminderChannel.description,
            title: title,
            body: body,
            importance: Importance.high,
            priority: Priority.high,
            largeIconBitmap: largeIcon,
          ),
        );
        final payload = jsonEncode({
          'type': 'model_test',
          'route': 'model_test',
          'target_id': testId,
          'academy_id': academyId,
        });

        // Compute an absolute instant in UTC so no device-timezone plugin is
        // needed; the notification still fires at the correct local moment.
        final scheduledUtc = fireAt.toUtc();
        try {
          await _plugin.zonedSchedule(
            id: _notificationId(testId),
            title: title,
            body: body,
            scheduledDate: tz.TZDateTime.from(scheduledUtc, tz.UTC),
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: payload,
          );
          scheduled = true;
          detail = '${_minutesLabel(minutesBefore)} আগে বিজ্ঞপ্তি পাবেন।';
        } catch (_) {
          // Exact alarms can be blocked on Android 12+. Fall back to an
          // inexact alarm; still a real local notification in most cases.
          try {
            await _plugin.zonedSchedule(
              id: _notificationId(testId),
              title: title,
              body: body,
              scheduledDate: tz.TZDateTime.from(scheduledUtc, tz.UTC),
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              payload: payload,
            );
            scheduled = true;
            detail = '${_minutesLabel(minutesBefore)} আগে বিজ্ঞপ্তি পাবেন।';
          } catch (_) {
            detail = 'বিজ্ঞপ্তি নির্ধারণ যায়নি; অ্যাপ খোলা থাকলে জানিয়ে দেব।';
          }
        }
      }
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
      detail = 'বিজ্ঞপ্তি নির্ধারণ যায়নি; অ্যাপ খোলা থাকলে জানিয়ে দেব।';
    }

    final stored = reminder.copyWith(scheduled: scheduled);
    final all = await _readAll()
      ..removeWhere(
        (item) =>
            item.testId == testId &&
            item.academyId == academyId &&
            item.studentId == studentId,
      )
      ..add(stored);
    await _save(all, scopeAcademyId: null);
    return ReminderResult(
      saved: true,
      scheduled: scheduled,
      message: 'রিমাইন্ডার সক্রিয় — $detail',
    );
  }

  static Future<void> remove({
    required String academyId,
    required String studentId,
    required String testId,
  }) async {
    final all = await _readAll()
      ..removeWhere(
        (item) =>
            item.testId == testId &&
            item.academyId == academyId &&
            item.studentId == studentId,
      );
    await _save(all, scopeAcademyId: null);
    try {
      await _ensureInitialized();
      await _plugin.cancel(id: _notificationId(testId));
    } catch (_) {}
  }

  static Future<void> cancelAll({
    required String academyId,
    required String studentId,
  }) async {
    final reminders = await load(academyId: academyId, studentId: studentId);
    for (final reminder in reminders) {
      await remove(
        academyId: academyId,
        studentId: studentId,
        testId: reminder.testId,
      );
    }
  }

  /// Reminders that should be surfaced in-app right now (also covers devices
  /// where exact alarms were unavailable).
  static Future<List<TestReminder>> dueNow({
    required String academyId,
    required String studentId,
  }) async {
    final reminders = await load(academyId: academyId, studentId: studentId);
    final now = DateTime.now();
    return reminders.where((item) {
      if (item.fireAt.isAfter(now) || !item.startAt.isAfter(now)) return false;
      final shown = item.lastShownAt;
      return shown == null || now.difference(shown).inMinutes >= 10;
    }).toList();
  }

  static Future<void> markTriggered({
    required String academyId,
    required String studentId,
    required String testId,
  }) async {
    final all = await _readAll();
    final index = all.indexWhere(
      (item) =>
          item.testId == testId &&
          item.academyId == academyId &&
          item.studentId == studentId,
    );
    if (index < 0) return;
    all[index] = all[index].copyWith(lastShownAt: DateTime.now());
    await _save(all, scopeAcademyId: null);
  }

  static String minutesLabel(int minutes) => _minutesLabel(minutes);

  static String _minutesLabel(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      return rest == 0 ? '$hours ঘণ্টা' : '$hours ঘণ্টা $rest মিনিট';
    }
    return '$minutes মিনিট';
  }

  static String _format(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }
}
