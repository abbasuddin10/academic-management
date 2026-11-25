import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/app_notification.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Unified inbox: notices + fee/attendance/exam/routine events for one student.
class StudentNotificationCenterView extends StatefulWidget {
  final String academyId;
  final String readerKey;
  final String className;
  final List<Notice> notices;
  final void Function(String route, String targetId) onOpen;

  const StudentNotificationCenterView({
    super.key,
    required this.academyId,
    required this.readerKey,
    required this.className,
    required this.notices,
    required this.onOpen,
  });

  @override
  State<StudentNotificationCenterView> createState() =>
      _StudentNotificationCenterViewState();
}

class _StudentNotificationCenterViewState
    extends State<StudentNotificationCenterView> {
  final NotificationRepository _events = NotificationRepository();
  final NoticeRepository _notices = NoticeRepository();

  List<AppNotification> _items = <AppNotification>[];
  final Map<String, Set<String>> _eventIdsByKey = <String, Set<String>>{};
  final Map<String, Set<String>> _noticeIdsByKey = <String, Set<String>>{};

  bool _loading = true;
  String? _filter; // null = all, otherwise a NotificationTypes value
  bool get _english =>
      Get.isRegistered<AppStateController>() &&
      AppStateController.to.isEnglish.value;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final events = await _events.fetch(
        widget.academyId,
        readerKey: widget.readerKey,
      );
      final noticeById = <String, Notice>{
        for (final notice in widget.notices)
          if (notice.id.isNotEmpty) notice.id: notice,
      };

      final merged = <AppNotification>[];
      final indexByKey = <String, int>{};
      _eventIdsByKey.clear();
      _noticeIdsByKey.clear();

      void remember(String key, {String? eventId, String? noticeId}) {
        if (eventId != null && eventId.isNotEmpty) {
          _eventIdsByKey.putIfAbsent(key, () => <String>{}).add(eventId);
        }
        if (noticeId != null && noticeId.isNotEmpty) {
          _noticeIdsByKey.putIfAbsent(key, () => <String>{}).add(noticeId);
        }
      }

      void addMerged(AppNotification item) {
        final key = _dedupeKey(item);
        final existingIndex = indexByKey[key];
        if (existingIndex == null) {
          indexByKey[key] = merged.length;
          merged.add(item);
          return;
        }
        // Same logical notice/event from two sources: keep one card and merge
        // its read state so a tapped/notification-read copy stays read.
        final existing = merged[existingIndex];
        merged[existingIndex] = existing.copyWith(
          isRead: existing.isRead || item.isRead,
        );
      }

      for (final event in events) {
        var item = event;
        if (event.type == NotificationTypes.notice) {
          final noticeId = event.targetId ?? event.id;
          final notice = noticeById[noticeId];
          final key = _dedupeKey(event);
          remember(key, eventId: event.id, noticeId: noticeId);
          if (notice != null) {
            remember(key, noticeId: notice.id);
            item = event.copyWith(isRead: event.isRead || notice.isRead);
          }
        }
        addMerged(item);
      }

      for (final notice in widget.notices) {
        final key = 'notice:${notice.id}';
        remember(key, noticeId: notice.id);
        final existingIndex = indexByKey[key];
        if (existingIndex != null) {
          final existing = merged[existingIndex];
          merged[existingIndex] = existing.copyWith(
            isRead: existing.isRead || notice.isRead,
          );
          continue;
        }
        indexByKey[key] = merged.length;
        merged.add(
          AppNotification(
            id: notice.id,
            academyId: widget.academyId,
            type: NotificationTypes.notice,
            title: notice.title,
            body: notice.description,
            targetId: notice.id,
            route: NotificationTypes.notice,
            createdAt:
                DateTime.tryParse(notice.raw['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            isRead: notice.isRead,
          ),
        );
      }

      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Notices are identified by their notice id (because `app_notifications`
  /// and `notices` both contain them). Other events use id + target + payload
  /// + second so repeat deliveries collapse without hiding real updates.
  String _dedupeKey(AppNotification item) {
    if (item.type == NotificationTypes.notice) {
      final id = (item.targetId ?? item.id).trim();
      return 'notice:${id.isEmpty ? item.id : id}';
    }
    final target = (item.targetId ?? '').trim();
    final stamp = item.createdAt.millisecondsSinceEpoch ~/ 1000;
    if (target.isNotEmpty) {
      return '${item.type}:$target:${item.title}:${item.body}:$stamp';
    }
    return '${item.type}:${item.id}:${item.title}:${item.body}:$stamp';
  }

  Set<String> _eventIdsFor(AppNotification item) {
    final stored = _eventIdsByKey[_dedupeKey(item)];
    final ids = stored == null ? <String>{} : <String>{...stored};
    if (ids.isEmpty && item.id.isNotEmpty) ids.add(item.id);
    return ids;
  }

  Set<String> _noticeIdsFor(AppNotification item) {
    final stored = _noticeIdsByKey[_dedupeKey(item)];
    final ids = stored == null ? <String>{} : <String>{...stored};
    if (item.type == NotificationTypes.notice &&
        (item.targetId ?? '').isNotEmpty) {
      ids.add(item.targetId!.trim());
    }
    return ids.where((id) => id.isNotEmpty).toSet();
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      setState(() {
        final i = _items.indexWhere((e) => e.id == item.id);
        if (i != -1) _items[i] = _items[i].copyWith(isRead: true);
      });
      final appState = Get.isRegistered<AppStateController>()
          ? AppStateController.to
          : null;
      if (item.type == NotificationTypes.notice) {
        appState?.decrementUnreadNoticeCount();
      } else if ((appState?.unreadActivityCount.value ?? 0) > 0) {
        appState!.unreadActivityCount.value =
            appState.unreadActivityCount.value - 1;
      }
      // Mark every hidden duplicate too, otherwise the same notice reappears
      // as unread after a refresh.
      await _persistReads(_noticeIdsFor(item), _eventIdsFor(item));
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onOpen(item.route, item.targetId ?? '');
  }

  Future<void> _markAll() async {
    final unread = _items.where((e) => !e.isRead).toList();
    if (unread.isEmpty) return;

    setState(() {
      _items = _items.map((e) => e.copyWith(isRead: true)).toList();
    });

    final appState = Get.isRegistered<AppStateController>()
        ? AppStateController.to
        : null;
    appState?.setUnreadNoticeCount(0);
    if (appState != null) appState.unreadActivityCount.value = 0;

    final noticeIds = <String>{};
    final eventIds = <String>{};
    for (final item in unread) {
      noticeIds.addAll(_noticeIdsFor(item));
      eventIds.addAll(_eventIdsFor(item));
    }
    await _persistReads(noticeIds, eventIds);
  }

  /// Never let a database/RLS failure turn "Mark all read" into an app crash.
  /// The UI is already updated optimistically; persistence is best-effort.
  Future<void> _persistReads(
    Set<String> noticeIds,
    Set<String> eventIds,
  ) async {
    final writes = <Future<void>>[];
    if (noticeIds.isNotEmpty) {
      writes.add(
        _notices.markAllAsRead(
          noticeIds.toList(),
          academyId: widget.academyId,
          readerKey: widget.readerKey,
        ),
      );
    }
    if (eventIds.isNotEmpty) {
      writes.add(
        _events.markAllAsRead(
          eventIds.toList(),
          academyId: widget.academyId,
          readerKey: widget.readerKey,
        ),
      );
    }
    for (final write in writes) {
      try {
        await write;
      } catch (_) {
        // Best effort: keep the inbox responsive even if read syncing fails.
      }
    }
  }

  List<AppNotification> get _visible => _filter == null
      ? _items
      : _items.where((e) => e.type == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(_english ? 'Notifications' : 'নোটিফিকেশন'),
        actions: [
          TextButton.icon(
            onPressed: _markAll,
            icon: const Icon(Icons.done_all, color: Colors.white, size: 20),
            label: Text(
              _english ? 'Mark all read' : 'সব পঠিত',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip(null, _english ? 'All' : 'সব'),
                _chip(NotificationTypes.notice, _english ? 'Notice' : 'নোটিস'),
                _chip(NotificationTypes.fee, _english ? 'Fee' : 'বেতন'),
                _chip(
                  NotificationTypes.attendance,
                  _english ? 'Attendance' : 'উপস্থিতি',
                ),
                _chip(
                  NotificationTypes.examRoutine,
                  _english ? 'Exam' : 'পরীক্ষা',
                ),
                _chip(
                  NotificationTypes.result,
                  _english ? 'Result' : 'রেজাল্ট',
                ),
                _chip(
                  NotificationTypes.classRoutine,
                  _english ? 'Routine' : 'রুটিন',
                ),
                _chip(
                  NotificationTypes.modelTest,
                  _english ? 'Model Test' : 'মডেল টেস্ট',
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                ? Center(
                    child: Text(
                      _english
                          ? 'No notifications yet.'
                          : 'এখনো কোনো নোটিফিকেশন নেই।',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _visible[index];
                        final accent = AppTheme.tileInkOf(
                          context,
                          _accentFor(item.type),
                        );
                        return Card(
                          color: item.isRead
                              ? AppTheme.surfaceOf(context)
                              : AppTheme.tileOf(
                                  context,
                                  AppTheme.brandOf(context),
                                ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: AppTheme.borderOf(context)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.tileOf(
                                context,
                                _accentFor(item.type),
                              ),
                              child: Icon(item.icon, color: accent, size: 20),
                            ),
                            title: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: item.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: AppTheme.inkOf(context),
                              ),
                            ),
                            subtitle: Text(
                              '${_english ? item.categoryEn : item.categoryBn} • ${item.body}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: item.isRead
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppTheme.brandOf(context),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                            onTap: () => _open(item),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String? value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    ),
  );

  Color _accentFor(String type) => switch (type) {
    NotificationTypes.fee => Colors.green,
    NotificationTypes.attendance => Colors.blue,
    NotificationTypes.examRoutine => Colors.indigo,
    NotificationTypes.result => Colors.purple,
    NotificationTypes.classRoutine => Colors.orange,
    NotificationTypes.modelTest => Colors.deepPurple,
    _ => Colors.teal,
  };
}
