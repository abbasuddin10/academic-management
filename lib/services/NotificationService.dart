import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // অ্যান্ড্রয়েড নোটিফিকেশন সেটিংস
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotificationsPlugin.initialize(
      settings:
          initSettings, // লেটেস্ট ভার্সনে 'settings:' নাম দিয়ে পাস করতে হয়
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          print("Clicked notice id: ${response.payload}");
        }
      },
    );

    // নোটিফিকেশন পার্মিশন চাওয়া
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ফোরগ্রাউন্ডে মেসেজ আসলে লোকাল নোটিফিকেশন দেখানোর জন্য
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _showLocalNotification(notification);
      }
    });

    // অ্যাপ ব্যাকগ্রাউন্ড থেকে ওপেন হলে
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      String? noticeId = message.data['notice_id'];
      if (noticeId != null) {
        print("Opening notice from background: $noticeId");
      }
    });
  }

  // লোকাল নোটিফিকেশন পপআপ বা ট্রেতে দেখানোর ফাংশন
  static void _showLocalNotification(RemoteNotification notification) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _localNotificationsPlugin.show(
      id: notification.hashCode, // লেটেস্ট ভার্সনে নামযুক্ত আর্গুমেন্ট দিতে হয়
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
    );
  }
}
