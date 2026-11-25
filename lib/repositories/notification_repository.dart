import 'dart:async';

import 'package:academy_management/models/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_repository.dart';

/// Per-recipient inbox for notices + academic/fee events, backed by
/// `public.app_notifications` (see migration 0003).
class NotificationRepository extends BaseRepository {
  static const String inboxTable = 'app_notifications';
  static const String devicesTable = 'student_devices';

  Future<List<AppNotification>> fetch(
    String academyId, {
    required String readerKey,
    int limit = 100,
  }) async {
    if (academyId.isEmpty || readerKey.isEmpty) return <AppNotification>[];
    try {
      final rows = await client
          .from(inboxTable)
          .select()
          .eq('academy_id', academyId)
          .eq('reader_key', readerKey)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map(
            (row) =>
                AppNotification.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } catch (_) {
      // Migration not applied yet: the notice-only pipeline still works.
      return <AppNotification>[];
    }
  }

  Future<int> getUnreadCount(
    String academyId, {
    required String readerKey,
  }) async {
    if (academyId.isEmpty || readerKey.isEmpty) return 0;
    try {
      final rows = await client
          .from(inboxTable)
          .select('id')
          .eq('academy_id', academyId)
          .eq('reader_key', readerKey)
          .isFilter('read_at', null)
          // Notices are already counted by NoticeRepository via `notices` +
          // `notice_reads`. Excluding their mirrored inbox rows here keeps the
          // combined bell at one unread per logical notice for every role.
          .neq('type', NotificationTypes.notice);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAsRead(
    String notificationId, {
    required String academyId,
    required String readerKey,
  }) async {
    if (notificationId.isEmpty || academyId.isEmpty || readerKey.isEmpty) {
      return;
    }
    try {
      await client
          .from(inboxTable)
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', notificationId)
          .eq('academy_id', academyId)
          .eq('reader_key', readerKey);
    } catch (_) {
      // Read-state failures are non-fatal; badge stays best-effort.
    }
  }

  Future<void> markAllAsRead(
    List<String> ids, {
    required String academyId,
    required String readerKey,
  }) async {
    final unique = ids.toSet().where((id) => id.isNotEmpty).toList();
    if (unique.isEmpty || academyId.isEmpty || readerKey.isEmpty) return;
    final stamp = DateTime.now().toIso8601String();
    try {
      for (final id in unique) {
        await client
            .from(inboxTable)
            .update({'read_at': stamp})
            .eq('id', id)
            .eq('academy_id', academyId)
            .eq('reader_key', readerKey);
      }
    } catch (_) {
      // Best effort.
    }
  }

  /// Registers/refreshes this device's FCM token for push delivery while the
  /// app is backgrounded or terminated.
  Future<void> registerDeviceToken({
    required String academyId,
    required String studentId,
    required String token,
    String platform = 'android',
  }) async {
    if (academyId.isEmpty || studentId.isEmpty || token.isEmpty) return;
    try {
      await client.from(devicesTable).upsert(<String, dynamic>{
        'academy_id': academyId,
        'student_id': studentId,
        'fcm_token': token,
        'platform': platform,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (_) {
      // Token sync failures never block login.
    }
  }

  /// Live unread counter for the inbox. Caller MUST dispose the handle.
  NotificationWatch watchUnreadCount({
    required String academyId,
    required String readerKey,
  }) {
    final controller = StreamController<int>.broadcast();

    Future<void> refresh() async {
      final count = await getUnreadCount(academyId, readerKey: readerKey);
      if (!controller.isClosed) controller.add(count);
    }

    final channel = client
        .channel(
          'activity-unread-$readerKey-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: inboxTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reader_key',
            value: readerKey,
          ),
          callback: (_) => unawaited(refresh()),
        )
        .subscribe();

    unawaited(refresh());
    return NotificationWatch._(client, controller, channel);
  }
}

/// Owns the realtime subscription for the activity badge.
class NotificationWatch {
  final SupabaseClient _client;
  final StreamController<int> _controller;
  final RealtimeChannel _channel;

  NotificationWatch._(this._client, this._controller, this._channel);

  Stream<int> get stream => _controller.stream;

  void dispose() {
    if (!_controller.isClosed) _controller.close();
    unawaited(_client.removeChannel(_channel));
  }
}
