import 'package:academy_management/config/app_theme.dart';
import 'dart:async';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/app_actions.dart';
import 'package:academy_management/services/fcm_token_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/attendance/attendance_page_view.dart';
import 'package:academy_management/views/exams/academy_result_management_view.dart';
import 'package:academy_management/views/exams/model_test_view.dart';
import 'package:academy_management/views/exams/teacher_routine_view.dart';
import 'package:academy_management/views/exams/question_create_view.dart';
import 'package:academy_management/views/attendance/student_attendance_page_view.dart';
import 'package:academy_management/views/exams/teacher_exam_routine_view.dart';
import 'package:academy_management/views/notices/notice_board_view.dart';
import 'package:academy_management/views/privacy_policy_view.dart';
import 'package:academy_management/views/settings/settings_view.dart';
import 'package:academy_management/views/teacher/teacher_profile.dart';
import 'package:academy_management/views/finance/teacher_salary_page.dart';
import 'package:academy_management/views/student/student_notification_center_view.dart';
import 'package:academy_management/widgets/notification_bell.dart';
import 'package:academy_management/widgets/theme_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart'; // 👈 অ্যাড প্যাকেজ ইমপোর্ট
import '../auth/login_view.dart';
import '../student/students_view.dart';

class TeacherHomeView extends StatefulWidget {
  final String userName;

  const TeacherHomeView({super.key, required this.userName});

  @override
  State<TeacherHomeView> createState() => _TeacherHomeViewState();
}

class _TeacherHomeViewState extends State<TeacherHomeView> {
  final supabase = Supabase.instance.client;

  String teacherId = '';
  String teacherName = '';
  String teacherEmail = '';
  String academyId = '';
  String _readerKey = '';
  String photoUrl = '';
  double monthlySalary = 0.0;
  double paidSalary = 0.0;
  double dueSalary = 0.0;
  bool isAttendanceGivenToday = false;
  bool hasInternet = true;

  List<Map<String, dynamic>> routines = [];
  Timer? _timer;
  DateTime _now = DateTime.now();

  BannerAd? _bannerAd; // 👈 ব্যানার অ্যাড ভেরিয়েবল
  bool _isBannerAdLoaded = false;

  final Map<int, String> _weekdaysMap = {
    DateTime.saturday: 'শনিবার',
    DateTime.sunday: 'রবিবার',
    DateTime.monday: 'সোমবার',
    DateTime.tuesday: 'মঙ্গলবার',
    DateTime.wednesday: 'বুধবার',
    DateTime.thursday: 'বৃহস্পতিবার',
    DateTime.friday: 'শুক্রবার',
  };

  List<Map<String, dynamic>> latestNotices = [];

  @override
  void initState() {
    super.initState();
    _checkInternetAndFetchData();

    AdService.loadInterstitialAd(); // 👈 ইন্টারস্টিশিয়াল অ্যাড লোড করা হলো
    _initBannerAd(); // 👈 ব্যানার অ্যাড ইনিশিয়ালাইজ

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  // 👈 ব্যানার অ্যাড সেটআপ ফাংশন
  void _initBannerAd() {
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerAd?.dispose(); // 👈 ব্যানার অ্যাড ডিসপোজ
    super.dispose();
  }

  Future<void> _checkInternetAndFetchData() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        setState(() {
          hasInternet = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          hasInternet = true;
        });
      }
      await _checkAuthAndFetchData();
    }
  }

  int _timeToMinutes(String timeStr) {
    try {
      timeStr = timeStr.trim().toUpperCase();
      bool isPM = timeStr.contains('PM');
      timeStr = timeStr.replaceAll('AM', '').replaceAll('PM', '').trim();
      List<String> parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      if (isPM && hour != 12) hour += 12;
      if (!isPM && hour == 12) hour = 0;

      return hour * 60 + minute;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _checkAuthAndFetchData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool? isTeacherLoggedIn = prefs.getBool('is_teacher_logged_in') ?? false;
      String? savedEmail = prefs.getString('teacher_email');

      if (!isTeacherLoggedIn || savedEmail == null || savedEmail.isEmpty) {
        Get.offAll(() => const LoginView());
        return;
      }

      teacherEmail = savedEmail;

      final userResponse = await supabase
          .from('users')
          .select()
          .eq('email', teacherEmail.trim())
          .maybeSingle();

      String tempId = '';
      String tempName = widget.userName;
      String tempAcademyId = '';
      double tempSalary = 0.0;
      String tempPhoto = '';

      if (userResponse != null) {
        tempId = userResponse['id']?.toString() ?? '';
        tempName = userResponse['full_name']?.toString() ?? widget.userName;
        tempAcademyId = userResponse['academy_id']?.toString() ?? '';
        tempSalary =
            double.tryParse(userResponse['salary']?.toString() ?? '0') ?? 0.0;
        tempPhoto = userResponse['photo_url']?.toString() ?? '';
      }

      bool tempAttendance = false;
      double tempPaid = 0.0;
      double tempDue = 0.0;
      List<Map<String, dynamic>> tempRoutines = [];
      List<Map<String, dynamic>> tempNotices = [];

      if (tempAcademyId.isNotEmpty) {
        final today = DateTime.now().toIso8601String().split('T')[0];

        try {
          final attendanceResponse = await supabase
              .from('teacher_attendance')
              .select('*')
              .eq('academy_id', tempAcademyId)
              .eq(
                'teacher_id',
                tempId,
              ) // 👈 email এর পরিবর্তে শিক্ষকের নিজস্ব id দিয়ে চেক করা হলো
              .eq('date', today);
          if ((attendanceResponse as List).isNotEmpty) {
            tempAttendance = true;
          }
        } catch (e) {
          debugPrint("Attendance fetch error: $e");
        }

        try {
          final salaryHistory = await supabase
              .from('teacher_salary_history')
              .select('amount')
              .eq('academy_id', tempAcademyId)
              .eq('teacher_id', tempId);

          for (var item in (salaryHistory as List)) {
            tempPaid +=
                double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
          }
        } catch (e) {
          debugPrint("Salary history fetch error: $e");
        }

        tempDue = tempSalary - tempPaid;
        if (tempDue < 0) tempDue = 0;

        try {
          final routineRes = await supabase
              .from('class_routines')
              .select()
              .eq('academy_id', tempAcademyId)
              .eq('teacher_id', tempId);

          tempRoutines = List<Map<String, dynamic>>.from(routineRes);
        } catch (e) {
          debugPrint("Routine fetch error: $e");
        }

        try {
          final noticeRes = await supabase
              .from('notices')
              .select('title, description, created_at')
              .eq('academy_id', tempAcademyId)
              .order('created_at', ascending: false)
              .limit(3);

          tempNotices = List<Map<String, dynamic>>.from(noticeRes);
        } catch (e) {
          debugPrint('Notice preview unavailable: $e');
        }
      }

      if (mounted) {
        setState(() {
          teacherId = tempId;
          teacherName = tempName;
          academyId = tempAcademyId;
          monthlySalary = tempSalary;
          paidSalary = tempPaid;
          dueSalary = tempDue;
          isAttendanceGivenToday = tempAttendance;
          routines = tempRoutines;
          latestNotices = tempNotices;
          photoUrl = tempPhoto;
        });
      }

      // Keep the live unread badge in sync for this teacher tenant, including
      // salary payments written to the shared app_notifications inbox.
      final appState = Get.isRegistered<AppStateController>()
          ? AppStateController.to
          : null;
      if (appState != null && tempAcademyId.isNotEmpty) {
        _readerKey = appState.readerKey.value?.isNotEmpty == true
            ? appState.readerKey.value!
            : SessionService.readerKeyFor(role: 'teacher', userId: tempId);
        appState.startNoticeWatch(
          academyId: tempAcademyId,
          role: 'teacher',
          readerKey: _readerKey,
        );
        appState.startActivityWatch(
          academyId: tempAcademyId,
          readerKey: _readerKey,
        );
        appState.refreshUnreadNoticeCount();
        appState.refreshUnreadActivityCount();
        unawaited(FcmTokenService.syncNow());
      }
    } catch (e) {
      debugPrint("Error fetching teacher data: $e");
    }
  }

  Future<void> _logout() async {
    // Removes only auth keys; device id / ad counters are preserved.
    await SessionService.signOut();

    if (mounted) {
      Get.offAll(() => const LoginView());
    }
  }

  /// Opens the same unified inbox students use, scoped to this teacher's
  /// reader key, so salary payments appear beside notices and mark read there.
  Future<void> _openNotificationCenter() async {
    if (academyId.isEmpty) {
      Get.snackbar(
        'ত্রুটি',
        'একাডেমি আইডি পাওয়া যায়নি!',
        backgroundColor: AppTheme.errorOf(context),
        colorText: AppTheme.onStatusOf(context),
      );
      return;
    }

    final readerKey = _readerKey.isNotEmpty
        ? _readerKey
        : SessionService.readerKeyFor(role: 'teacher', userId: teacherId);
    _readerKey = readerKey;

    List<Notice> notices = <Notice>[];
    try {
      notices = await NoticeRepository().fetch(
        academyId,
        readerKey: readerKey,
        role: 'teacher',
      );
    } catch (_) {
      // An offline notice fetch must not block the notification inbox.
    }
    if (!mounted) return;

    await Get.to(
      () => StudentNotificationCenterView(
        academyId: academyId,
        readerKey: readerKey,
        className: '',
        notices: notices,
        onOpen: (route, _) => _openNotificationTarget(route),
      ),
    );
  }

  void _openNotificationTarget(String route) {
    if (route == 'teacher_salary' || route == 'fee') {
      unawaited(
        Get.to(
          () => TeacherSalaryPageView(
            academyId: academyId,
            teacherEmail: teacherEmail,
            teacherName: teacherName,
            teacherId: teacherId,
          ),
        ),
      );
      return;
    }
    unawaited(
      Get.to(() => NoticeBoardView(academyId: academyId, userRole: 'teacher')),
    );
  }

  @override
  Widget build(BuildContext context) {
    String todayBengali = _weekdaysMap[_now.weekday] ?? 'শনিবার';

    int currentTotalSeconds =
        (_now.hour * 3600) + (_now.minute * 60) + _now.second;
    int currentMinutes = _now.hour * 60 + _now.minute;

    List<Map<String, dynamic>> todayRoutines = routines.where((r) {
      return (r['day'] ?? '') == todayBengali && !(r['is_off'] ?? false);
    }).toList();

    todayRoutines.sort((a, b) {
      int timeA = _timeToMinutes(a['start_time'] ?? '00:00 AM');
      int timeB = _timeToMinutes(b['start_time'] ?? '00:00 AM');
      return timeA.compareTo(timeB);
    });

    Map<String, dynamic>? currentClass;
    Map<String, dynamic>? nextClass;

    for (var r in todayRoutines) {
      int startMin = _timeToMinutes(r['start_time'] ?? '');
      int endMin = _timeToMinutes(r['end_time'] ?? '');

      if (currentMinutes >= startMin && currentMinutes <= endMin) {
        currentClass = r;
      } else if (startMin > currentMinutes && nextClass == null) {
        nextClass = r;
      }
    }

    String remainingTimeText = '';
    if (currentClass != null) {
      int endMin = _timeToMinutes(currentClass['end_time'] ?? '');
      int endTotalSeconds = endMin * 60;
      int remainingSeconds = endTotalSeconds - currentTotalSeconds;

      if (remainingSeconds > 0) {
        int remMins = remainingSeconds ~/ 60;
        int remSecs = remainingSeconds % 60;
        remainingTimeText = 'শেষ হতে বাকি: $remMinsমি $remSecsসে';
      } else {
        remainingTimeText = 'ক্লাস শেষের পথে';
      }
    }

    // Resolved on every build, so flipping the theme in Settings instantly
    // repaints this screen, its drawer and all of its cards.
    final isDark = AppTheme.isDark(context);
    final surface = AppTheme.surfaceOf(context);
    final brand = AppTheme.brandOf(context);
    final appBarForeground = isDark ? AppTheme.nightInk : Colors.white;
    final heroGradient = LinearGradient(
      colors: isDark
          ? const <Color>[Color(0xFF0F3D3A), Color(0xFF0B2E2B)]
          : const <Color>[Color(0xFF00796B), Color(0xFF004D40)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? AppTheme.nightSurfaceAlt : brand,
        title: Text(
          'শিক্ষক প্যানেল',
          style: TextStyle(
            color: appBarForeground,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // প্রফাইল পিকচার সার্কেল আইকন (বামে ও উপরে সবুজ ডট সহ) এবং ক্লিক লজিক
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
            child: GestureDetector(
              onTap: () async {
                if (academyId.isNotEmpty && teacherId.isNotEmpty) {
                  await Get.to(
                    () => TeacherProfileView(
                      teacherId: teacherId,
                      academyId: academyId,
                    ),
                  );
                  _checkAuthAndFetchData();
                } else {
                  Get.snackbar(
                    "ত্রুটি",
                    "শিক্ষকের তথ্য লোড হয়নি, কিছুক্ষণ অপেক্ষা করুন।",
                    backgroundColor: AppTheme.errorOf(context),
                    colorText: AppTheme.onStatusOf(context),
                  );
                }
              },
              child: Stack(
                children: [
                  // প্রফাইল ছবি বা ডিফল্ট আইকন
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isDark
                        ? AppTheme.nightCanvas
                        : Colors.white,
                    child: ClipOval(
                      child:
                          (photoUrl.isNotEmpty && photoUrl.startsWith('http'))
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.fill,
                              width: 36,
                              height: 36,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.person,
                                  size: 20,
                                  color: brand,
                                );
                              },
                            )
                          : Icon(Icons.person, size: 20, color: brand),
                    ),
                  ),
                  // বামে ও উপরে এক্টিভ সবুজ ডট
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent, // সবুজ রঙ
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          ThemeModeToggle(color: appBarForeground),
          // নোটিফিকেশন আইকন — লাইভ আনরিড ব্যাজ সহ
          NotificationBell(
            icon: Icons.notifications,
            color: appBarForeground,
            onTap: _openNotificationCenter,
          ),
        ],
      ),

      drawer: Drawer(
        child: Column(
          children: [
            // কাস্টম হেডার সেকশন (অ্যাপবারের সাথে মিল রেখে সলিড টিল কালার এবং তথ্য মাঝবরাবর করা হয়েছে)
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: 48,
                bottom: 20,
                left: 16,
                right: 16,
              ),
              color: isDark
                  ? AppTheme.nightSurfaceAlt
                  : brand, // অ্যাপবারের সাথে মিল রাখা হয়েছে
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: isDark
                        ? AppTheme.nightCanvas
                        : Colors.white,
                    child: ClipOval(
                      child:
                          (photoUrl.isNotEmpty && photoUrl.startsWith('http'))
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.fill,
                              width: 64,
                              height: 64,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.person,
                                  size: 32,
                                  color: brand,
                                );
                              },
                            )
                          : Icon(Icons.person, size: 32, color: brand),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    teacherName.isNotEmpty ? teacherName : 'শিক্ষক',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: appBarForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teacherEmail.isNotEmpty ? teacherEmail : '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: appBarForeground.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ড্রয়ারের মূল মেনু ও অতিরিক্ত অপশনসমূহ
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  // --- মেইন ফিচারস ---
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.home,
                      color: AppTheme.tileInkOf(context, Colors.teal),
                    ),
                    title: const Text(
                      'হোম',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () => Navigator.pop(context),
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.groups,
                      color: AppTheme.tileInkOf(context, Colors.blue),
                    ),
                    title: const Text(
                      'ছাত্রছাত্রী তালিকা',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const StudentsView(userRole: 'teacher'));
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.fact_check,
                      color: AppTheme.tileInkOf(context, Colors.green),
                    ),
                    title: const Text(
                      'ছাত্রছাত্রীদের হাজিরা',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (academyId.isNotEmpty) {
                        Get.to(
                          () => StudentAttendancePageView(
                            academyId: academyId,
                            teacherName: teacherName.isNotEmpty
                                ? teacherName
                                : widget.userName,
                          ),
                        );
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: AppTheme.errorOf(context),
                          colorText: AppTheme.onStatusOf(context),
                        );
                      }
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.notifications_active,
                      color: AppTheme.tileInkOf(context, Colors.orange),
                    ),
                    title: const Text(
                      'নোটিশ বোর্ড',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (academyId.isNotEmpty) {
                        Get.to(
                          () => NoticeBoardView(
                            academyId: academyId,
                            userRole: 'teacher',
                          ),
                        );
                      }
                    },
                  ),

                  // --- ডিভাইডার দিয়ে আলাদা সেকশন ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Divider(
                      thickness: 1,
                      color: AppTheme.borderOf(context),
                    ),
                  ),

                  // --- এক্সট্রা সেটিংস ও পলিসি সেকশন ---
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.settings_outlined,
                      color: AppTheme.tileInkOf(context, Colors.blueGrey),
                    ),
                    title: const Text(
                      'সেটিংস',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const SettingsView());
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.feedback_outlined,
                      color: AppTheme.tileInkOf(context, Colors.amber),
                    ),
                    title: const Text(
                      'ফিডব্যাক দিন',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      AppActions.showFeedbackDialog();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.privacy_tip,
                      color: AppTheme.tileInkOf(context, Colors.teal),
                    ),
                    title: const Text('প্রাইভেসি পলিসি'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PrivacyPolicyView(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.share_outlined,
                      color: AppTheme.tileInkOf(context, Colors.teal),
                    ),
                    title: const Text(
                      'অ্যাপ শেয়ার করুন',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      AppActions.showShareUnavailable();
                    },
                  ),
                ],
              ),
            ),

            Divider(height: 1),

            // লগআউট অপশন
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: AppTheme.tileOf(context, Colors.red),
                leading: Icon(Icons.logout, color: AppTheme.errorOf(context)),
                title: Text(
                  'লগআউট',
                  style: TextStyle(
                    color: AppTheme.errorOf(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onTap: _logout,
              ),
            ),

            // একদম নিচে অ্যাপের ভার্সন প্রদর্শন
            Padding(
              padding: EdgeInsets.only(bottom: 16.0, top: 4.0),
              child: Text(
                'App Version: 1.0.0',
                style: TextStyle(
                  color: AppTheme.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!hasInternet)
            Container(
              width: double.infinity,
              color: AppTheme.errorOf(context),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    color: AppTheme.onStatusOf(context),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ইন্টারনেট সংযোগ নেই! দয়া করে ইন্টারনেট কানেক্ট করুন।',
                    style: TextStyle(
                      color: AppTheme.onStatusOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _checkInternetAndFetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: heroGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isAttendanceGivenToday
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isAttendanceGivenToday
                                    ? 'স্ট্যাটাসঃ একটিভ (হাজিরা সম্পন্ন)'
                                    : 'স্ট্যাটাসঃ উপস্থিত হননি',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white30, height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.fiber_manual_record,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'রানিং ক্লাস:',
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (currentClass != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              remainingTimeText,
                                              style: const TextStyle(
                                                color: Color.fromARGB(
                                                  255,
                                                  27,
                                                  26,
                                                  26,
                                                ),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentClass != null
                                          ? '${currentClass['class_name']} (${currentClass['subject'] ?? 'বিষয় নেই'})'
                                          : 'এই মুহূর্তে কোনো ক্লাস চলছে না',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (currentClass != null)
                                      Text(
                                        'পিরিয়ড: ${currentClass['period_name']} (${currentClass['start_time']} - ${currentClass['end_time']})',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.upcoming,
                                color: Colors.lightGreenAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'পরবর্তী ক্লাস:',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      nextClass != null
                                          ? 'সময়: ${nextClass['start_time']} | ${nextClass['class_name']} (${nextClass['subject'] ?? 'বিষয় নেই'})'
                                          : 'আজ আর কোনো ক্লাস নেই',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'একাডেমি ম্যানেজমেন্ট',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      children: [
                        _buildMenuCard(
                          title: 'ছাত্রছাত্রী তালিকা',
                          icon: Icons.groups,
                          color: AppTheme.tileOf(context, Colors.blue),
                          iconColor: AppTheme.tileInkOf(context, Colors.blue),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                // 👈 অ্যাড উইথ ট্র্যাকিং (সর্বোচ্চ ৩টি দৈনিক)
                                Get.to(() => StudentsView(userRole: 'teacher'));
                              },
                            );
                          },
                        ),
                        _buildMenuCard(
                          title: 'ছাত্রছাত্রীদের হাজিরা',
                          icon: Icons.fact_check,
                          color: AppTheme.tileOf(context, Colors.green),
                          iconColor: AppTheme.tileInkOf(context, Colors.green),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty) {
                                  Get.to(
                                    () => StudentAttendancePageView(
                                      academyId: academyId,
                                      teacherName: teacherName.isNotEmpty
                                          ? teacherName
                                          : widget.userName,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),
                        _buildMenuCard(
                          title: 'আমার হাজিরা',
                          icon: Icons.how_to_reg,
                          color: AppTheme.tileOf(context, Colors.teal),
                          iconColor: AppTheme.tileInkOf(context, Colors.teal),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () async {
                                if (academyId.isNotEmpty) {
                                  // 👈 ১. এখানে await ব্যবহার করা হয়েছে কি না নিশ্চিত করুন
                                  await Get.to(
                                    () => AttendancePageView(
                                      academyId: academyId,
                                      userRole: 'teacher',
                                    ),
                                  );

                                  // 👈 ২. পেজ থেকে ফিরে আসার সাথে সাথে ডাটা রিলোড হবে
                                  _checkAuthAndFetchData();
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),

                        _buildMenuCard(
                          title: 'ক্লাস রুটিন',
                          icon: Icons.schedule,
                          color: AppTheme.tileOf(context, Colors.purple),
                          iconColor: AppTheme.tileInkOf(context, Colors.purple),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty &&
                                    teacherId.isNotEmpty) {
                                  Get.to(
                                    () => TeacherRoutineView(
                                      academyId: academyId,
                                      teacherId: teacherId,
                                      teacherName: teacherName.isNotEmpty
                                          ? teacherName
                                          : widget.userName,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "শিক্ষকের আইডি বা একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),

                        _buildMenuCard(
                          title: 'পরীক্ষার ফলাফল',
                          icon: Icons.assessment,
                          color: AppTheme.tileOf(context, Colors.indigo),
                          iconColor: AppTheme.tileInkOf(context, Colors.indigo),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty) {
                                  Get.to(
                                    () => AcademyResultManagementView(
                                      academyId: academyId,
                                      currentUserId: teacherId,
                                      currentUserName: teacherName.isNotEmpty
                                          ? teacherName
                                          : widget.userName,
                                      isReadOnly: true,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),
                        _buildMenuCard(
                          title: 'এক্সাম রুটিন',
                          icon: Icons.event_note,
                          color: AppTheme.tileOf(context, Colors.cyan),
                          iconColor: AppTheme.tileInkOf(context, Colors.cyan),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty) {
                                  Get.to(
                                    () => TeacherExamRoutineView(
                                      academyId: academyId,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),

                        _buildMenuCard(
                          title: 'বেতন ও বকেয়া',
                          icon: Icons.account_balance_wallet,
                          color: AppTheme.tileOf(context, Colors.lightBlue),
                          iconColor: AppTheme.tileInkOf(
                            context,
                            Colors.lightBlue,
                          ),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty &&
                                    teacherEmail.isNotEmpty &&
                                    teacherId.isNotEmpty) {
                                  Get.to(
                                    () => TeacherSalaryPageView(
                                      academyId: academyId,
                                      teacherEmail: teacherEmail,
                                      teacherName: teacherName,
                                      teacherId: teacherId,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "শিক্ষকের তথ্য লোড হয়নি, কিছুক্ষণ অপেক্ষা করুন।",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),
                        _buildMenuCard(
                          title: 'পরীক্ষা তৈরি',
                          icon: Icons.assignment_add,
                          color: AppTheme.tileOf(context, Colors.teal),
                          iconColor: AppTheme.tileInkOf(context, Colors.teal),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                if (academyId.isNotEmpty &&
                                    teacherId.isNotEmpty) {
                                  Get.to(
                                    () => ModelTestView(
                                      academyId: academyId,
                                      currentUserId: teacherId,
                                      currentUserName: teacherName.isNotEmpty
                                          ? teacherName
                                          : widget.userName,
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "অপেক্ষা করুন",
                                    "শিক্ষকের তথ্য লোড হচ্ছে, অনুগ্রহ করে একটু পরে আবার চেষ্টা করুন।",
                                    backgroundColor: AppTheme.warningOf(
                                      context,
                                    ),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),
                        _buildMenuCard(
                          icon: Icons.quiz_rounded,
                          title: 'প্রশ্ন তৈরি',
                          color: AppTheme.tileOf(context, Colors.deepPurple),
                          iconColor: AppTheme.tileInkOf(
                            context,
                            Colors.deepPurple,
                          ),
                          onTap: () {
                            AdService.showAdWithTracking(
                              onComplete: () {
                                final currentUserId = teacherId.isNotEmpty
                                    ? teacherId
                                    : (supabase.auth.currentUser?.id ?? '');

                                if (academyId.isNotEmpty) {
                                  Get.to(
                                    () => QuestionCreateView(
                                      academyId: academyId,
                                      currentUserId: currentUserId,
                                      currentUserName: teacherName.isNotEmpty
                                          ? teacherName
                                          : widget.userName,
                                      userRole: 'teacher',
                                    ),
                                  );
                                } else {
                                  Get.snackbar(
                                    "ত্রুটি",
                                    "একাডেমি আইডি পাওয়া যায়নি!",
                                    backgroundColor: AppTheme.errorOf(context),
                                    colorText: AppTheme.onStatusOf(context),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    // const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'সর্বশেষ নোটিশসমূহ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (academyId.isNotEmpty) {
                              Get.to(
                                () => NoticeBoardView(
                                  academyId: academyId,
                                  userRole: 'teacher',
                                ),
                              );
                            }
                          },
                          child: const Text('সব দেখুন'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    latestNotices.isEmpty
                        ? Card(
                            elevation: 0,
                            color: surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: AppTheme.borderOf(context),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text('কোনো নোটিশ পাওয়া যায়নি'),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: latestNotices.length,
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final notice = latestNotices[index];
                              return Card(
                                elevation: 0,
                                margin: EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: AppTheme.borderOf(context),
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: brand,
                                    child: Icon(
                                      Icons.notifications,
                                      color: AppTheme.onStatusOf(context),
                                    ),
                                  ),
                                  title: Text(
                                    notice['title'] ?? 'শিরোনামহীন',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    notice['description'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () {
                                    if (academyId.isNotEmpty) {
                                      Get.to(
                                        () => NoticeBoardView(
                                          academyId: academyId,
                                          userRole: 'teacher',
                                        ),
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
          ),
          // 👈 বটমে ফিক্সড ব্যানার অ্যাড উইজেট
          if (_isBannerAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
