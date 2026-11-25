import 'dart:async';
import 'package:academy_management/config/app_config.dart';
import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/services/fcm_token_service.dart';
import 'package:academy_management/services/notification_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/student/student_home_view.dart';
import 'package:academy_management/views/teacher/teacher_home_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:academy_management/views/auth/login_view.dart';
import 'package:academy_management/views/dashboard/shared_dashboard.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ব্যাকগ্রাউন্ড হ্যান্ডলার
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.handleBackgroundMessage(message);
}

/// Restores a student screen only after the cached record is validated in the
/// database — a local boolean alone is never trusted.
Future<Widget?> _restoreStudentScreen(SharedPreferences prefs) async {
  final studentFlag = prefs.getBool(SessionService.studentLoggedInKey) ?? false;
  if (!studentFlag) return null;

  final studentId = prefs.getString(SessionService.studentIdKey) ?? '';
  final academyId = prefs.getString(SessionService.studentAcademyIdKey) ?? '';
  final className = prefs.getString(SessionService.studentClassKey) ?? '';
  final roll = prefs.getString(SessionService.studentRollKey) ?? '';

  final isValid = await SessionService.studentRecordIsValid(
    studentId: studentId,
    academyId: academyId,
    className: className,
    roll: roll,
  );

  if (!isValid) {
    await SessionService.signOut();
    return null;
  }

  return StudentHomeView(
    studentName: prefs.getString(SessionService.studentNameKey) ?? '',
    academyName: prefs.getString(SessionService.studentAcademyKey) ?? '',
    className: className,
    roll: roll,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        authDomain: AppConfig.firebaseAuthDomain,
        projectId: AppConfig.firebaseProjectId,
        storageBucket: AppConfig.firebaseStorageBucket,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        appId: AppConfig.firebaseAppId,
        measurementId: AppConfig.firebaseMeasurementId,
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // ব্যাকগ্রাউন্ড হ্যান্ডলার রেজিস্টার
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // নোটিফিকেশন সার্ভিস ইনিশিয়ালাইজ করুন
  await NotificationService.initialize();

  // সুপাবেস ইনিশিয়ালাইজেশন (কী --dart-define বা নিরাপদ ডিফল্ট থেকে আসে)
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  // Session restoration: local flags are NEVER trusted on their own. Every
  // cached session is validated against the authoritative Supabase records.
  final prefs = await SharedPreferences.getInstance();
  Widget initialScreen = const LoginView();

  final currentUser = Supabase.instance.client.auth.currentUser;

  if (currentUser != null && currentUser.isAnonymous) {
    // Teacher / student session opened at login. Role comes from the server.
    final appSession = await SessionService.fetchAppSession();
    final role = appSession?['role']?.toString() ?? '';

    if (SessionService.isTeacherRole(role)) {
      initialScreen = TeacherHomeView(
        userName: (appSession?['display_name'] ?? 'শিক্ষক').toString(),
      );
    } else if (role == 'student') {
      final restored = await _restoreStudentScreen(prefs);
      if (restored != null) initialScreen = restored;
    } else {
      await SessionService.signOut();
    }
  } else if (currentUser?.email != null) {
    // Authenticated account: role comes from the database, never from the
    // fact that sign-in succeeded.
    final email = currentUser!.email!;
    final userRow = await SessionService.fetchUserRow(email);
    final role = userRow?['role']?.toString() ?? '';
    final name = (userRow?['full_name'] ?? userRow?['name'] ?? email)
        .toString();

    if (role == 'super_admin') {
      initialScreen = SharedDashboard(
        role: role,
        userName: name,
        currentUserId: userRow?['id']?.toString(),
      );
    } else if (SessionService.isTeacherRole(role)) {
      initialScreen = TeacherHomeView(userName: name);
    } else {
      // Authenticated identity without an authorised application role.
      await SessionService.signOut();
    }
  } else {
    final teacherFlag =
        prefs.getBool(SessionService.teacherLoggedInKey) ?? false;
    final teacherEmail = prefs.getString(SessionService.teacherEmailKey) ?? '';

    if (teacherFlag && teacherEmail.isNotEmpty) {
      final userRow = await SessionService.fetchUserRow(teacherEmail);
      final role = userRow?['role']?.toString() ?? '';

      if (SessionService.isTeacherRole(role)) {
        final name = (userRow?['full_name'] ?? userRow?['name'] ?? 'শিক্ষক')
            .toString();
        initialScreen = TeacherHomeView(userName: name);
      } else {
        await SessionService.signOut();
      }
    } else {
      final restored = await _restoreStudentScreen(prefs);
      if (restored != null) initialScreen = restored;
    }
  }

  final noticeContext = await SessionService.noticeContext();
  final appState = Get.put(AppStateController(), permanent: true);
  appState.setSession(
    academyId: noticeContext.academyId.isNotEmpty
        ? noticeContext.academyId
        : (prefs.getString(SessionService.academyIdKey) ??
              prefs.getString(SessionService.studentAcademyIdKey)),
    role: noticeContext.role,
    readerKey: noticeContext.readerKey,
  );
  appState.startNoticeWatch(
    academyId: appState.academyId.value ?? '',
    role: noticeContext.role,
    readerKey: noticeContext.readerKey,
    className: noticeContext.className,
  );
  appState.startActivityWatch(
    academyId: appState.academyId.value ?? '',
    readerKey: noticeContext.readerKey,
  );
  // Best-effort: keeps this device reachable while the app is closed.
  unawaited(FcmTokenService.syncNow());

  runApp(MyApp(initialScreen: initialScreen));

  // Notification that launched the app from a terminated state.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await NotificationService.handleTap(
        NotificationService.encodeData(initialMessage.data),
      );
    }
  });
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    final appState = Get.isRegistered<AppStateController>()
        ? Get.find<AppStateController>()
        : null;

    Widget buildMaterialApp(String preference) => GetMaterialApp(
      title: 'Academy Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: AppTheme.themeModeFor(preference),
      home: initialScreen,
    );

    // Obx makes theme switching instant on every open screen. When no
    // controller is registered (e.g. the lightweight widget test) skip it so
    // GetX does not report an unused reactive scope.
    if (appState == null) return buildMaterialApp('light');
    return Obx(() => buildMaterialApp(appState.themePreference.value));
  }
}
