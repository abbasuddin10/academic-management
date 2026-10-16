import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'views/auth/login_view.dart';
import 'views/dashboard/shared_dashboard.dart';
import 'views/student/student_home_view.dart';
import 'views/teacher/teacher_home_view.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/notification_service.dart'; // নোটিফিকেশন সার্ভিস ইমপোর্ট করুন

// ব্যাকগ্রাউন্ড হ্যান্ডলার
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Background message received: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCzBC-yibWgIHzy5VTrV6p0qnRB-ExE18",
        authDomain: "academy-manager-65b2a.firebaseapp.com",
        projectId: "academy-manager-65b2a",
        storageBucket: "academy-manager-65b2a.firebasestorage.app",
        messagingSenderId: "291092236875",
        appId: "1:291092236875:web:31521e88aa4125ad705bce",
        measurementId: "G-JJK4PTEWM",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // ব্যাকগ্রাউন্ড হ্যান্ডলার রেজিস্টার
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // নোটিফিকেশন সার্ভিস ইনিশিয়ালাইজ করুন (সব লজিক এখন আলাদা ফাইলের ভেতরে থাকবে)
  await NotificationService.initialize();

  // সুপাবেস ইনিশিয়ালাইজেশন
  await Supabase.initialize(
    url: 'https://rtyrbxpvntfaetvynfvf.supabase.co',
    anonKey: 'sb_publishable_IBDoDckksGkwsImjXu8W9g_rR6rRpiI',
  );

  // শেয়ার্ড প্রিফারেন্স থেকে লগইন স্ট্যাটাস চেক করা
  final prefs = await SharedPreferences.getInstance();
  bool isStudentLoggedIn = prefs.getBool('is_student_logged_in') ?? false;
  bool isTeacherLoggedIn = prefs.getBool('is_teacher_logged_in') ?? false;

  Widget initialScreen = const LoginView();

  if (isStudentLoggedIn) {
    String studentName = prefs.getString('student_name') ?? '';
    String studentAcademy = prefs.getString('student_academy') ?? '';
    String studentClass = prefs.getString('student_class') ?? '';
    String studentRoll = prefs.getString('student_roll') ?? '';

    initialScreen = StudentHomeView(
      studentName: studentName,
      academyName: studentAcademy,
      className: studentClass,
      roll: studentRoll,
    );
  } else if (isTeacherLoggedIn) {
    String teacherEmail = prefs.getString('teacher_email') ?? '';
    String teacherName = 'শিক্ষক';
    try {
      if (teacherEmail.isNotEmpty) {
        final teacherData = await Supabase.instance.client
            .from('users')
            .select('full_name, name')
            .eq('email', teacherEmail)
            .maybeSingle();

        if (teacherData != null) {
          teacherName =
              teacherData['full_name'] ?? teacherData['name'] ?? 'শিক্ষক';
        }
      }
    } catch (e) {
      print("Error fetching teacher name on startup: $e");
    }

    initialScreen = TeacherHomeView(userName: teacherName);
  } else {
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null && session.user.email != null) {
      try {
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('email', session.user.email!)
            .single();

        String role = userData['role'] ?? 'teacher';
        String fullName = userData['full_name'] ?? 'User';

        initialScreen = SharedDashboard(role: role, userName: fullName);
      } catch (e) {
        initialScreen = const LoginView();
      }
    }
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Academy Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: initialScreen,
    );
  }
}

