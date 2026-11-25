import 'dart:async';

import 'package:academy_management/models/notice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_repository.dart';

class NoticeRepository extends BaseRepository {
  static const String readTable = 'notice_reads';

  /// Whether a notice is addressed to [role]/[className]. Teachers and admins
  /// receive all academy notices; students only receive academy-wide notices
  /// and notices for their own class.
  static bool isTargeted(
    Map<String, dynamic> notice, {
    required String role,
    String? className,
  }) {
    if (role != 'student') return true;

    final target = notice['target_type']?.toString() ?? '';
    if (target.isEmpty ||
        target == 'everyone' ||
        target == 'all' ||
        target == 'all_students') {
      return true;
    }
    if (target == 'class') {
      final noticeClass =
          notice['target_class']?.toString().trim().toLowerCase() ?? '';
      final studentClass = className?.trim().toLowerCase() ?? '';
      return noticeClass.isNotEmpty && noticeClass == studentClass;
    }
    return false;
  }

  /// Fetches notices and merges the current recipient's `notice_reads` rows.
  /// Passing [role]/[className] also applies audience targeting.
  Future<List<Notice>> fetch(
    String academyId, {
    String? readerKey,
    String? role,
    String? className,
  }) async {
    final rows = await client
        .from('notices')
        .select()
        .eq('academy_id', academyId)
        .order('created_at', ascending: false);

    final notices = (rows as List)
        .map((row) => Notice.fromMap(Map<String, dynamic>.from(row as Map)))
        .where(
          (notice) =>
              role == null ||
              isTargeted(notice.raw, role: role, className: className),
        )
        .toList();

    if (readerKey == null || readerKey.isEmpty) return notices;
    final readIds = await _readNoticeIds(academyId, readerKey);
    return notices
        .map((notice) => notice.copyWith(isRead: readIds.contains(notice.id)))
        .toList();
  }

  Future<Set<String>> _readNoticeIds(String academyId, String readerKey) async {
    try {
      final rows = await client
          .from(readTable)
          .select('notice_id')
          .eq('academy_id', academyId)
          .eq('reader_key', readerKey);
      return (rows as List)
          .map((row) => row['notice_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      // Migration not applied (or a transient failure): treat everything as
      // unread rather than blocking the notice board.
      return <String>{};
    }
  }

  Future<int> getUnreadCount(
    String academyId, {
    String? readerKey,
    String? role,
    String? className,
  }) async {
    if (academyId.isEmpty) return 0;
    final notices = await fetch(
      academyId,
      readerKey: readerKey,
      role: role,
      className: className,
    );
    return notices.where((notice) => !notice.isRead).length;
  }

  /// Idempotent single insert/upsert; RLS guarantees the reader key belongs to
  /// the current session and to the correct academy.
  Future<void> markAsRead(
    String noticeId, {
    required String academyId,
    required String readerKey,
  }) async {
    if (noticeId.isEmpty || academyId.isEmpty || readerKey.isEmpty) return;
    await client.from(readTable).upsert(<String, dynamic>{
      'academy_id': academyId,
      'notice_id': noticeId,
      'reader_key': readerKey,
    }, onConflict: 'notice_id,reader_key');
  }

  /// Batch insert for the "Mark all as read" action.
  Future<void> markAllAsRead(
    List<String> noticeIds, {
    required String academyId,
    required String readerKey,
  }) async {
    final uniqueIds = noticeIds.toSet().where((id) => id.isNotEmpty).toList();
    if (uniqueIds.isEmpty || academyId.isEmpty || readerKey.isEmpty) return;

    await client
        .from(readTable)
        .upsert(
          uniqueIds
              .map(
                (id) => <String, dynamic>{
                  'academy_id': academyId,
                  'notice_id': id,
                  'reader_key': readerKey,
                },
              )
              .toList(),
          onConflict: 'notice_id,reader_key',
        );
  }

  /// Live unread counter scoped by academy, reader and audience. The returned
  /// handle owns the Realtime channel and MUST be disposed by the caller.
  NoticeUnreadWatch watchUnreadCount({
    required String academyId,
    required String readerKey,
    String? role,
    String? className,
  }) {
    final controller = StreamController<int>.broadcast();

    Future<void> refresh() async {
      try {
        final count = await getUnreadCount(
          academyId,
          readerKey: readerKey,
          role: role,
          className: className,
        );
        if (!controller.isClosed) controller.add(count);
      } catch (_) {
        // Keep the last good value; a later event will retry.
      }
    }

    final channel = client
        .channel(
          'notice-unread-$readerKey-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'academy_id',
            value: academyId,
          ),
          callback: (_) => unawaited(refresh()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: readTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reader_key',
            value: readerKey,
          ),
          callback: (_) => unawaited(refresh()),
        )
        .subscribe();

    unawaited(refresh());
    return NoticeUnreadWatch._(client, controller, channel);
  }

  Future<void> delete(String noticeId, String academyId) async {
    if (academyId.isEmpty) {
      throw ArgumentError.value(academyId, 'academyId', 'must not be empty');
    }
    await client
        .from('notices')
        .delete()
        .eq('id', noticeId)
        .eq('academy_id', academyId);
  }
}

/// Owns a single Realtime subscription and the broadcast count stream.
class NoticeUnreadWatch {
  final SupabaseClient _client;
  final StreamController<int> _controller;
  final RealtimeChannel _channel;

  NoticeUnreadWatch._(this._client, this._controller, this._channel);

  Stream<int> get stream => _controller.stream;

  void dispose() {
    if (!_controller.isClosed) _controller.close();
    unawaited(_client.removeChannel(_channel));
  }
}
