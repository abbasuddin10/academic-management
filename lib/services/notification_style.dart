import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Single source of truth for the look of every Android notification.
///
/// Android 5+ requires the *small* icon to be a white-on-transparent silhouette;
/// that is the app icon shown at the top-left of the notification. The larger
/// avatar on the right is the specific institute logo of the target student.
/// Keeping both here means FCM pushes, local notices and model-test reminders
/// all look identical.
abstract final class AppNotificationStyle {
  /// Keep the existing channel id so older installs keep their settings.
  static const String pushChannelId = 'high_importance_channel';
  static const String reminderChannelId = 'model_test_reminders';

  /// White-on-transparent app silhouette: Android draws this top-left.
  static const String smallIcon = '@drawable/ic_stat_academy';

  /// Generic large icon used only when a student has no usable logo URL.
  static const String largeIcon = 'ic_notification_logo';
  static const AndroidBitmap<Object> fallbackLargeIcon =
      DrawableResourceAndroidBitmap(largeIcon);

  static const Color brand = Color(0xFF1E40AF);
  static const String summary = 'অ্যাকাডেমি ম্যানেজমেন্ট';

  static const AndroidNotificationChannel pushChannel =
      AndroidNotificationChannel(
        pushChannelId,
        'অ্যাকাডেমি নোটিফিকেশন',
        description: 'নোটিশ, বেতন, উপস্থিতি ও পরীক্ষার আপডেট',
        importance: Importance.max,
        enableLights: true,
        ledColor: brand,
      );

  static const AndroidNotificationChannel reminderChannel =
      AndroidNotificationChannel(
        reminderChannelId,
        'মডেল টেস্ট রিমাইন্ডার',
        description: 'আসন্ন মডেল টেস্টের জন্য সময়মতো অনুস্মারণ',
        importance: Importance.high,
        enableLights: true,
        ledColor: brand,
      );

  /// Downloads the student's institute logo and returns the right-side bitmap.
  ///
  /// Never throws: a missing/invalid URL, a failed request, empty bytes or an
  /// unsupported payload all return [fallbackLargeIcon] so a notification is
  /// always still shown.
  static Future<AndroidBitmap<Object>> largeIconFromUrl(String? url) async {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return fallbackLargeIcon;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return fallbackLargeIcon;
    }

    try {
      final response = await Dio().get<List<int>>(
        trimmed,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const <String, dynamic>{'Accept': 'image/*'},
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final status = response.statusCode ?? 0;
      final bytes = response.data;
      if (status < 200 || status >= 300) return fallbackLargeIcon;
      if (bytes == null || bytes.isEmpty) return fallbackLargeIcon;

      final image = Uint8List.fromList(bytes);
      if (!_looksLikeSupportedImage(image)) return fallbackLargeIcon;
      return ByteArrayAndroidBitmap(image);
    } catch (e) {
      debugPrint('Notification institute logo load skipped: $e');
      return fallbackLargeIcon;
    }
  }

  /// Guards against an error page being handed to the notification plugin as
  /// if it were a bitmap. Unknown formats simply use the generic large icon.
  static bool _looksLikeSupportedImage(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4e &&
        b[3] == 0x47 &&
        b[4] == 0x0d &&
        b[5] == 0x0a &&
        b[6] == 0x1a &&
        b[7] == 0x0a) {
      return true; // PNG
    }
    if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
      return true; // JPEG
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x38 &&
        (b[4] == 0x37 || b[4] == 0x39) &&
        b[5] == 0x61) {
      return true; // GIF
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true; // WebP
    }
    return b.length >= 2 && b[0] == 0x42 && b[1] == 0x4d; // BMP
  }

  static AndroidNotificationDetails details({
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    String? channelDescription,
    Importance importance = Importance.max,
    Priority priority = Priority.high,
    bool autoCancel = true,
    AndroidBitmap<Object>? largeIconBitmap,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      // Top-left app icon. This never changes per student.
      icon: smallIcon,
      // Right-side institute logo of the target student, with safe fallback.
      largeIcon: largeIconBitmap ?? fallbackLargeIcon,
      color: brand,
      autoCancel: autoCancel,
      category: AndroidNotificationCategory.message,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: summary,
      ),
    );
  }
}
