import 'package:academy_management/models/app_notification.dart';
import 'package:academy_management/services/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppNotification model', () {
    test('maps an unread database row and derives category labels', () {
      final item = AppNotification.fromMap(<String, dynamic>{
        'id': 'n-1',
        'academy_id': 'a-1',
        'type': 'fee',
        'title': 'বেতন আপডেট',
        'body': 'জানুয়ারি — ৳ ১০০০',
        'route': 'fee',
        'created_at': '2026-01-01T10:00:00Z',
        'read_at': null,
      });

      expect(item.isRead, isFalse);
      expect(item.categoryBn, 'বেতন');
      expect(item.categoryEn, 'Fee');
      expect(item.route, 'fee');
    });

    test('read_at marks the item read and copyWith preserves fields', () {
      final item = AppNotification.fromMap(<String, dynamic>{
        'id': 'n-2',
        'academy_id': 'a-1',
        'type': 'result',
        'title': 'ফলাফল',
        'body': '',
        'route': 'result',
        'created_at': '2026-01-02T10:00:00Z',
        'read_at': '2026-01-02T11:00:00Z',
      });

      expect(item.isRead, isTrue);
      expect(item.copyWith(isRead: false).isRead, isFalse);
      expect(item.copyWith(isRead: false).type, 'result');
    });
  });

  group('Notification payload parsing', () {
    test('parses an FCM event data payload', () {
      final payload = NotificationRouter.parsePayload(
        '{"type":"fee","route":"fee","target_id":"fee-9","academy_id":"a-1"}',
      );

      expect(payload, isNotNull);
      expect(payload!.type, 'fee');
      expect(payload.route, 'fee');
      expect(payload.id, 'fee-9');
      expect(payload.isNotice, isFalse);
    });

    test('parses legacy notice payloads', () {
      final jsonPayload = NotificationRouter.parsePayload(
        '{"notice_id":"notice-3"}',
      );
      expect(jsonPayload!.isNotice, isTrue);
      expect(jsonPayload.id, 'notice-3');

      final bare = NotificationRouter.parsePayload('123|academy-1');
      expect(bare!.type, NotificationTypes.notice);
      expect(bare.id, '123');

      final keyed = NotificationRouter.parsePayload('notice_id=456');
      expect(keyed!.id, '456');
    });
  });
}
