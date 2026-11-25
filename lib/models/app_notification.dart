import 'package:flutter/material.dart';

/// One row in the unified recipient notification inbox.
///
/// Covers notices plus student events and teacher salary payments produced by
/// Supabase triggers.
class AppNotification {
  final String id;
  final String academyId;
  final String type;
  final String title;
  final String body;
  final String? targetId;
  final String route;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.academyId,
    required this.type,
    required this.title,
    required this.body,
    this.targetId,
    required this.route,
    required this.createdAt,
    this.isRead = false,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
    id: map['id']?.toString() ?? '',
    academyId: map['academy_id']?.toString() ?? '',
    type: map['type']?.toString() ?? 'notice',
    title: map['title']?.toString() ?? '',
    body: map['body']?.toString() ?? '',
    targetId: map['target_id']?.toString(),
    route: map['route']?.toString() ?? map['type']?.toString() ?? 'notice',
    createdAt:
        DateTime.tryParse(map['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    isRead: map['read_at'] != null,
  );

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    academyId: academyId,
    type: type,
    title: title,
    body: body,
    targetId: targetId,
    route: route,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );

  /// Bengali category tag for the notification center.
  String get categoryBn => switch (type) {
    'fee' => 'বেতন',
    'attendance' => 'উপস্থিতি',
    'exam_routine' => 'পরীক্ষার রুটিন',
    'result' => 'রেজাল্ট',
    'class_routine' => 'ক্লাস রুটিন',
    'model_test' => 'মডেল টেস্ট',
    _ => 'নোটিস',
  };

  /// English category tag for the notification center.
  String get categoryEn => switch (type) {
    'fee' => 'Fee',
    'attendance' => 'Attendance',
    'exam_routine' => 'Exam Routine',
    'result' => 'Result',
    'class_routine' => 'Class Routine',
    'model_test' => 'Model Test',
    _ => 'Notice',
  };

  IconData get icon => switch (type) {
    'fee' => Icons.payments_rounded,
    'attendance' => Icons.how_to_reg_rounded,
    'exam_routine' => Icons.calendar_month_rounded,
    'result' => Icons.assignment_turned_in_rounded,
    'class_routine' => Icons.schedule_rounded,
    'model_test' => Icons.quiz_rounded,
    _ => Icons.campaign_rounded,
  };
}

/// Known event categories shared by the database, push payloads and UI.
abstract final class NotificationTypes {
  static const String notice = 'notice';
  static const String fee = 'fee';
  static const String modelTest = 'model_test';
  static const String attendance = 'attendance';
  static const String examRoutine = 'exam_routine';
  static const String result = 'result';
  static const String classRoutine = 'class_routine';

  static const Set<String> all = <String>{
    notice,
    fee,
    modelTest,
    attendance,
    examRoutine,
    result,
    classRoutine,
  };
}
