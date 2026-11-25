import 'dart:convert';

import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/app_notification.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/repositories/notification_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import 'fcm_token_service.dart';
import 'notification_router.dart';
import 'notification_style.dart';
import 'session_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _initializeLocalNotifications();

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FcmTokenService.listenForRefresh();

    // Foreground messages are never drawn by Android itself, so always render
    // our branded local notification exactly once.
    FirebaseMessaging.onMessage.listen((message) async {
      await _showFromRemote(message, foreground: true);
      _refreshBadges();
    });

    // Background -> foreground via tap.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => handleTap(encodeData(message.data)),
    );
  }

  /// Entry point for `@pragma('vm:entry-point')` background messages.
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    await Firebase.initializeApp();
    await _initializeLocalNotifications();

    // Our Edge Function now sends data-only pushes, which Android will NOT
    // display on its own. Older notification-type pushes are skipped here
    // because the FCM SDK already drew them; the manifest gives those the same
    // branded small icon/color as a fallback.
    await _showFromRemote(message, foreground: false);
  }

  /// Serialises the FCM `data` map into a single payload string.
  static String encodeData(Map<String, dynamic> data) => jsonEncode(data);

  /// Marks the tapped item read (optimistically, with rollback) and navigates.
  static Future<void> handleTap(String? payload) async {
    final parsed = NotificationRouter.parsePayload(payload);
    if (parsed == null || parsed.id.isEmpty) return;

    try {
      final context = await SessionService.noticeContext();
      final appState = Get.isRegistered<AppStateController>()
          ? AppStateController.to
          : null;

      if (context.academyId.isNotEmpty) {
        if (parsed.isNotice) {
          await _markNoticeRead(parsed.id, context, appState);
        } else {
          // Data-only pushes carry the real inbox id separately from the
          // navigation target; prefer it so the badge/row turn read correctly.
          final eventId = parsed.notificationId.isNotEmpty
              ? parsed.notificationId
              : parsed.id;
          await _markEventRead(eventId, context, appState);
        }
      }
    } catch (e) {
      debugPrint('Notification read sync skipped: $e');
    }

    await NotificationRouter.handlePayload(payload);
  }

  static Future<void> _markNoticeRead(
    String noticeId,
    NoticeContext context,
    AppStateController? appState,
  ) async {
    final repository = NoticeRepository();
    final notices = await repository.fetch(
      context.academyId,
      readerKey: context.readerKey,
      role: context.role,
      className: context.className,
    );
    Notice? target;
    for (final notice in notices) {
      if (notice.id == noticeId) {
        target = notice;
        break;
      }
    }
    if (target == null || target.isRead) return;

    appState?.decrementUnreadNoticeCount();
    try {
      await repository.markAsRead(
        noticeId,
        academyId: context.academyId,
        readerKey: context.readerKey,
      );
    } catch (_) {
      appState?.incrementUnreadNoticeCount();
    }
  }

  static Future<void> _markEventRead(
    String eventId,
    NoticeContext context,
    AppStateController? appState,
  ) async {
    final events = await NotificationRepository().fetch(
      context.academyId,
      readerKey: context.readerKey,
    );
    final target = events.where((e) => e.id == eventId).firstOrNullSafe;
    if (target == null || target.isRead) return;

    if (appState != null && appState.unreadActivityCount.value > 0) {
      appState.unreadActivityCount.value =
          appState.unreadActivityCount.value - 1;
    }
    await NotificationRepository().markAsRead(
      eventId,
      academyId: context.academyId,
      readerKey: context.readerKey,
    );
  }

  /// Backward-compatible wrapper for existing notice-only call sites.
  static Future<void> handleNoticeTap(String? payload) => handleTap(payload);

  static void _refreshBadges() {
    if (!Get.isRegistered<AppStateController>()) return;
    AppStateController.to.refreshUnreadNoticeCount();
    AppStateController.to.refreshUnreadActivityCount();
  }

  static Future<void> _initializeLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings(AppNotificationStyle.smallIcon),
    );

    await _localNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        handleTap(response.payload);
      },
    );

    final android = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(AppNotificationStyle.pushChannel);
    await android?.createNotificationChannel(
      AppNotificationStyle.reminderChannel,
    );
  }

  static Future<void> _showFromRemote(
    RemoteMessage message, {
    required bool foreground,
  }) async {
    final systemNotification = message.notification;
    final isDataOnly = systemNotification == null;
    final forcedLocal = message.data['show_local']?.toString() == 'true';

    // In the background, a notification-type FCM message is already visible.
    // Rendering it again would show the same notice twice in the tray.
    if (!foreground && !isDataOnly && !forcedLocal) return;

    final title =
        (message.data['title']?.toString().isNotEmpty ?? false
                ? message.data['title']
                : systemNotification?.title)
            ?.toString() ??
        'নতুন নোটিফিকেশন';
    final body =
        (message.data['body']?.toString().isNotEmpty ?? false
                ? message.data['body']
                : systemNotification?.body)
            ?.toString() ??
        '';

    await _showLocalNotification(title: title, body: body, data: message.data);
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      // The Edge Function resolves the target student's institute logo and
      // sends its URL. Older payloads may only carry academy_id; resolve that
      // locally when possible. A missing/invalid URL uses the generic fallback.
      final logoUrl = await _resolveInstituteLogoUrl(data);
      final largeIcon = await AppNotificationStyle.largeIconFromUrl(logoUrl);
      await _showWithLogo(
        title: title,
        body: body,
        data: data,
        largeIcon: largeIcon,
      );
    } catch (e) {
      debugPrint('Local notification display failed: $e');
    }
  }

  static Future<void> _showWithLogo({
    required String title,
    required String body,
    required Map<String, dynamic> data,
    required AndroidBitmap<Object> largeIcon,
  }) async {
    final id = _notificationId(data, title, body);
    final payload = encodeData(data);

    Future<void> show(AndroidBitmap<Object> icon) =>
        _localNotificationsPlugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AppNotificationStyle.details(
              channelId: AppNotificationStyle.pushChannelId,
              channelName: AppNotificationStyle.pushChannel.name,
              channelDescription: AppNotificationStyle.pushChannel.description,
              title: title,
              body: body,
              largeIconBitmap: icon,
            ),
          ),
          payload: payload,
        );

    try {
      await show(largeIcon);
    } catch (e) {
      // A corrupt remote bitmap must never stop the notification entirely.
      debugPrint('Institute logo failed, retrying with fallback icon: $e');
      await show(AppNotificationStyle.fallbackLargeIcon);
    }
  }

  static Future<String?> _resolveInstituteLogoUrl(
    Map<String, dynamic> data,
  ) async {
    final pushed =
        _readText(data['institute_logo_url']) ??
        _readText(data['academy_logo_url']);
    if (pushed != null) return pushed;

    final academyId = _readText(data['academy_id']);
    if (academyId == null) return null;
    try {
      final academy = await AcademyRepository().fetchById(academyId);
      return _readText(academy?.logoUrl);
    } catch (e) {
      // Background isolates have no Supabase client. The pushed URL (when
      // present) is authoritative, so this is only a best-effort fallback.
      debugPrint('Notification institute logo lookup skipped: $e');
      return null;
    }
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// A stable id makes duplicate deliveries replace each other instead of
  /// piling up as two identical rows in the shade.
  static int _notificationId(
    Map<String, dynamic> data,
    String title,
    String body,
  ) {
    final parsed = int.tryParse(data['notification_id']?.toString() ?? '');
    if (parsed != null) return parsed.abs() % 1000000000;
    final key = '${data['type'] ?? ''}|${data['target_id'] ?? ''}|$title|$body';
    return key.hashCode.abs() % 1000000000;
  }
}

/// Small helper avoiding a dependency on the `collection` package here.
extension _FirstOrNullSafe on Iterable<AppNotification> {
  AppNotification? get firstOrNullSafe => isEmpty ? null : first;
}
