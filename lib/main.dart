import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'views/auth/login_view.dart';
import 'views/dashboard/shared_dashboard.dart';
import 'views/dashboard/student_home_view.dart';
import 'views/dashboard/teacher_home_view.dart'; // শিক্ষক ভিউ ইমপোর্ট করা হলো

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ১. ফায়ারবেস ইনিশিয়ালাইজ করুন
  await Firebase.initializeApp();

  // সুপাবেস ইনিশিয়ালাইজেশন
  await Supabase.initialize(
    url: 'https://rtyrbxpvntfaetvynfvf.supabase.co',
    anonKey: 'sb_publishable_IBDoDckksGkwsImjXu8W9g_rR6rRpiI',
  );

  // শেয়ার্ড প্রিফারেন্স থেকে লগইন স্ট্যাটাস চেক করা
  final prefs = await SharedPreferences.getInstance();
  bool isStudentLoggedIn = prefs.getBool('is_student_logged_in') ?? false;
  bool isTeacherLoggedIn =
      prefs.getBool('is_teacher_logged_in') ??
      false; // শিক্ষকের লগইন স্ট্যাটাস চেক

  // প্রথমে ডিফল্ট হিসেবে LoginView সেট করা হলো
  Widget initialScreen = const LoginView();

  if (isStudentLoggedIn) {
    // যদি শিক্ষার্থী লগইন করা থাকে
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
    // যদি শিক্ষক লগইন করা থাকে (অ্যাপ রিস্টার্ট দিলেও আর এডমিন পেজে যাবে না)
    String teacherEmail = prefs.getString('teacher_email') ?? '';

    // ডাটাবেজ থেকে শিক্ষকের সঠিক নামটি ফেচ করে নিয়ে আসা
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
    // সুপার এডমিন বা অন্যান্য Supabase Auth ইউজারদের জন্য চেক করা
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
