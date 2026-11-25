import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/app_notification.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/app_actions.dart';
import 'package:academy_management/services/fcm_token_service.dart';
import 'package:academy_management/views/admin/academy_ai_assistant_view.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/auth/login_view.dart';
import 'package:academy_management/views/exams/student_result_view.dart';
import 'package:academy_management/views/attendance/student_attendance_view.dart';
import 'package:academy_management/views/notices/student_complaint_view.dart';
import 'package:academy_management/views/notices/notice_board_view.dart';
import 'package:academy_management/views/exams/student_exam_routine_view.dart';
import 'package:academy_management/views/finance/student_fee_details_view.dart';
import 'package:academy_management/views/exams/student_model_test.dart';
import 'package:academy_management/views/privacy_policy_view.dart';
import 'package:academy_management/views/settings/settings_view.dart';
import 'package:academy_management/views/student/student_teachers_view.dart';
import 'package:academy_management/views/student/student_notification_center_view.dart';
import 'package:academy_management/widgets/notification_bell.dart';
import 'package:academy_management/widgets/theme_mode_toggle.dart';
import 'package:academy_management/views/exams/student_routine_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentHomeView extends StatefulWidget {
  final String studentName;
  final String academyName;
  final String className;
  final String roll;

  /// Optional deep-link arguments supplied by a push notification tap.
  final String? initialNotificationRoute;
  final String? initialTargetId;

  const StudentHomeView({
    super.key,
    required this.studentName,
    required this.academyName,
    required this.className,
    required this.roll,
    this.initialNotificationRoute,
    this.initialTargetId,
  });

  @override
  State<StudentHomeView> createState() => _StudentHomeViewState();
}

class _StudentHomeViewState extends State<StudentHomeView> {
  bool isLoading = true;
  bool hasError = false;
  Map<String, dynamic>? studentDetails;
  List<Map<String, dynamic>> noticesList = [];
  List<Map<String, dynamic>> feeHistoryList = [];

  String _todayAttendanceStatus = 'তথ্য নেই';
  String _academyId = '';
  String _readerKey = '';

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    fetchAllData();
    AdService.loadInterstitialAd();

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
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> fetchAllData() async {
    try {
      setState(() {
        hasError = false;
      });

      final supabase = Supabase.instance.client;

      final studentResponseList = await supabase
          .from('students')
          .select()
          .ilike('name', widget.studentName.trim())
          .eq('roll', widget.roll.trim())
          .limit(1);

      Map<String, dynamic>? studentResponse;
      if (studentResponseList.isNotEmpty) {
        studentResponse = studentResponseList.first;
      } else {
        final fallbackResponse = await supabase
            .from('students')
            .select()
            .eq('roll', widget.roll.trim())
            .limit(1);

        if (fallbackResponse.isNotEmpty) {
          studentResponse = fallbackResponse.first;
        }
      }

      if (studentResponse != null) {
        String studentId = studentResponse['id'].toString();

        // সফলভাবে ডাটা ফেচ হওয়ার পর SharedPreferences-এ আইডিগুলো আপডেট করে রাখা যাতে ভবিষ্যতে ব্যাকআপ হিসেবে থাকে
        final prefs = await SharedPreferences.getInstance();
        if (studentResponse['academy_id'] != null) {
          await prefs.setString(
            'student_academy_id',
            studentResponse['academy_id'].toString(),
          );
        }
        await prefs.setString('student_id', studentId);

        final feeResponse = await supabase
            .from('student_fee_history')
            .select()
            .eq('student_id', studentId);

        feeHistoryList = List<Map<String, dynamic>>.from(feeResponse);

        String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final attendanceResponse = await supabase
            .from('student_attendance')
            .select('status')
            .eq('student_id', studentId)
            .eq('date', currentDate)
            .maybeSingle();

        if (attendanceResponse != null) {
          String status = attendanceResponse['status']?.toString() ?? '';
          if (status == 'Present') {
            _todayAttendanceStatus = 'উপস্থিত';
          } else if (status == 'Absent') {
            _todayAttendanceStatus = 'অনুপস্থিত';
          } else {
            _todayAttendanceStatus = status;
          }
        } else {
          _todayAttendanceStatus = 'অনুপস্থিত';
        }
      }

      final academyId = studentResponse?['academy_id']?.toString() ?? '';
      _academyId = academyId;
      final noticeResponse = await supabase
          .from('notices')
          .select()
          .eq('academy_id', academyId)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> filteredNotices = [];
      String studentClass = widget.className.trim().toLowerCase();

      for (var notice in (noticeResponse as List)) {
        String targetType = notice['target_type']?.toString() ?? '';
        String targetClass =
            notice['target_class']?.toString().trim().toLowerCase() ?? '';

        if (targetType == 'all_students' || targetType == 'everyone') {
          filteredNotices.add(notice);
        } else if (targetType == 'class' && targetClass == studentClass) {
          filteredNotices.add(notice);
        }
      }

      if (!mounted) return;

      setState(() {
        studentDetails = studentResponse ?? {};
        noticesList = filteredNotices;
        isLoading = false;
        hasError = false;
      });

      // Live unread badge for this student (academy + class scoped).
      final appState = Get.isRegistered<AppStateController>()
          ? AppStateController.to
          : null;
      if (appState != null && academyId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        _readerKey = appState.readerKey.value?.isNotEmpty == true
            ? appState.readerKey.value!
            : SessionService.readerKeyFor(
                role: 'student',
                userId: prefs.getString(SessionService.studentIdKey) ?? '',
              );
        appState.startNoticeWatch(
          academyId: academyId,
          role: 'student',
          readerKey: _readerKey,
          className: widget.className,
        );
        appState.startActivityWatch(
          academyId: academyId,
          readerKey: _readerKey,
        );
        appState.refreshUnreadActivityCount();

        // Defensive token refresh: covers logins that happened offline or a
        // token that rotated while the app was closed. The same device token
        // is what lets the send-push Edge Function reach this student for
        // notices AND for fee/attendance/exam/routine events.
        unawaited(FcmTokenService.syncNow());

        // Handle a push tap that launched/reopened this screen.
        final route = widget.initialNotificationRoute;
        if (route != null && route.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _openNotificationRoute(route, widget.initialTargetId ?? '');
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  /// Marks a notice read for this student with an optimistic badge update.
  Future<void> _markNoticeRead(String noticeId) async {
    if (noticeId.isEmpty || _academyId.isEmpty || _readerKey.isEmpty) return;
    final appState = Get.isRegistered<AppStateController>()
        ? AppStateController.to
        : null;
    appState?.decrementUnreadNoticeCount();
    try {
      await NoticeRepository().markAsRead(
        noticeId,
        academyId: _academyId,
        readerKey: _readerKey,
      );
    } catch (_) {
      appState?.incrementUnreadNoticeCount();
    }
  }

  /// Opens the relevant student screen for a push notification category.
  /// All arguments come from the current session/prefs, with safe fallbacks.
  void _openNotificationRoute(String route, String targetId) {
    try {
      final academyId = _academyId;
      if (academyId.isEmpty) return;
      final studentId = studentDetails?['id']?.toString() ?? '';

      switch (route) {
        case NotificationTypes.fee:
          _navigateToFeeDetailsPage();
          break;
        case NotificationTypes.attendance:
          Get.to(
            () => StudentAttendanceView(
              studentId: studentId,
              studentName: widget.studentName,
            ),
          );
          break;
        case NotificationTypes.examRoutine:
          Get.to(
            () => StudentExamRoutineView(
              academyId: academyId,
              className: widget.className,
            ),
          );
          break;
        case NotificationTypes.result:
          Get.to(
            () => StudentResultView(
              academyId: academyId,
              className: widget.className,
              studentRoll: widget.roll,
              studentName: widget.studentName,
            ),
          );
          break;
        case NotificationTypes.classRoutine:
          Get.to(
            () => StudentRoutineView(
              academyId: academyId,
              className: widget.className,
            ),
          );
          break;
        case NotificationTypes.modelTest:
          Get.to(
            () => StudentModelTestView(
              academyId: academyId,
              className: widget.className,
              studentId: studentId,
              studentName: widget.studentName,
              studentRoll: widget.roll,
              initialTestId: targetId.isEmpty ? null : targetId,
            ),
          );
          break;
        default:
          Get.to(
            () => NoticeBoardView(academyId: academyId, userRole: 'student'),
          );
      }
    } catch (e) {
      debugPrint('Notification route fallback: $e');
      Get.snackbar(
        'তথ্য',
        'এই নোটিফিকেশনটি খোলা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  void _openNotificationCenter() {
    if (_academyId.isEmpty) {
      Get.snackbar(
        'ত্রুটি',
        'একাডেমি আইডি পাওয়া যায়নি।',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    Get.to(
      () => StudentNotificationCenterView(
        academyId: _academyId,
        readerKey: _readerKey,
        className: widget.className,
        notices: noticesList
            .map((row) => Notice.fromMap(Map<String, dynamic>.from(row)))
            .toList(),
        onOpen: _openNotificationRoute,
      ),
    );
  }

  // একক নোটিশ সম্পূর্ণ দেখার জন্য ডায়ালগ বা ভিউ ফাংশন
  void _showSingleNoticeDetail(Map<String, dynamic> notice) {
    _markNoticeRead(notice['id']?.toString() ?? '');
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: Colors.blue, size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        notice['title'] ?? 'নোটিশ শিরোনাম নেই',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.inkOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 20),
                Text(
                  notice['description'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.inkOf(context),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    notice['created_at'] != null
                        ? 'প্রকাশের তারিখ: ${notice['created_at'].toString().substring(0, 10)}'
                        : '',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Get.back(),
                    child: Text('বন্ধ করুন'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAllNoticesDialog() {
    Get.to(
      () => Scaffold(
        appBar: AppBar(
          title: Text('সকল নোটিশ'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        body: noticesList.isEmpty
            ? Center(
                child: Text(
                  'এই মুহূর্তে কোনো নোটিশ নেই।',
                  style: TextStyle(color: AppTheme.mutedOf(context)),
                ),
              )
            : ListView.builder(
                itemCount: noticesList.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final notice = noticesList[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showSingleNoticeDetail(notice),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.campaign,
                                  color: Colors.indigo,
                                  size: 22,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    notice['title'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppTheme.inkOf(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text(
                              notice['description'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedOf(context),
                              ),
                            ),
                            Divider(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                notice['created_at'] != null
                                    ? notice['created_at'].toString().substring(
                                        0,
                                        10,
                                      )
                                    : '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.mutedOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _navigateToFeeDetailsPage() {
    double monthlyFee = 0.0;
    if (studentDetails?['monthly_fee'] != null) {
      monthlyFee =
          double.tryParse(studentDetails!['monthly_fee'].toString()) ?? 0.0;
    }

    String studentId = studentDetails?['id']?.toString() ?? '';

    Get.to(
      () => StudentFeeDetailsView(
        studentId: studentId,
        studentName: widget.studentName,
        roll: widget.roll,
        monthlyFee: monthlyFee,
        feeHistoryList: feeHistoryList,
      ),
    );
  }

  Future<void> _logoutStudent() async {
    try {
      // Removes only auth keys; unrelated app settings are preserved.
      await SessionService.signOut();
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        Get.offAll(() => const LoginView());
      }
    } catch (e) {
      debugPrint('Logout Error: $e');
    }
  }

  void _showLogoutDialog() {
    Get.defaultDialog(
      title: "লগআউট",
      middleText: "আপনি কি অ্যাকাউন্ট থেকে বের হতে চান?",
      textConfirm: "হ্যাঁ",
      textCancel: "না",
      confirmTextColor: Colors.white,
      buttonColor: Colors.indigo,
      onConfirm: () {
        Get.back();
        Future.delayed(Duration(milliseconds: 150), () {
          _logoutStudent();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isPresent = _todayAttendanceStatus == 'উপস্থিত';

    String? profileImageUrl = studentDetails?['image_url'];

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'শিক্ষার্থী ড্যাশবোর্ড',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final academyId =
                  prefs.getString(SessionService.studentAcademyIdKey) ?? '';
              if (academyId.isEmpty) {
                Get.snackbar(
                  'ত্রুটি',
                  'একাডেমি আইডি পাওয়া যায়নি।',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              }
              Get.to(() => AcademyAiAssistantView(academyId: academyId));
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            label: const Text(
              'Ask',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          ThemeModeToggle(color: Colors.white),
          NotificationBell(
            icon: Icons.notifications_active_outlined,
            onTap: _openNotificationCenter,
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 48,
                bottom: 20,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo, Colors.indigo],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.surfaceOf(context),
                    backgroundImage:
                        (profileImageUrl != null && profileImageUrl.isNotEmpty)
                        ? NetworkImage(profileImageUrl)
                        : null,
                    child: (profileImageUrl == null || profileImageUrl.isEmpty)
                        ? Text(
                            widget.studentName.isNotEmpty
                                ? widget.studentName[0]
                                : 'S',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.studentName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.academyName,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.dashboard_rounded,
                      color: Colors.indigo,
                    ),
                    title: const Text(
                      'ড্যাশবোর্ড',
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
                    leading: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.indigo,
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
                      _showAllNoticesDialog();
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.green,
                    ),
                    title: const Text(
                      'বেতন হিসাব',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToFeeDetailsPage();
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.calendar_today_rounded,
                      color: Colors.teal,
                    ),
                    title: const Text(
                      'উপস্থিতি রিপোর্ট',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      String studentId =
                          studentDetails?['id']?.toString() ?? '';
                      Get.to(
                        () => StudentAttendanceView(
                          studentId: studentId,
                          studentName: widget.studentName,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.schedule_rounded,
                      color: Colors.blue,
                    ),
                    title: const Text(
                      'ক্লাশ রুটিন',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      String academyId = studentDetails?['academy_id'] ?? '';
                      Get.to(
                        () => StudentRoutineView(
                          academyId: academyId,
                          className: widget.className,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.supervisor_account_rounded,
                      color: Colors.purple,
                    ),
                    title: const Text(
                      'শিক্ষকগণ',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      String academyId = studentDetails?['academy_id'] ?? '';
                      Get.to(
                        () => StudentTeachersView(
                          academyId: academyId,
                          academyName: widget.academyName,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.report_problem_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'অভিযোগ বা মতামত',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      String academyId = studentDetails?['academy_id'] ?? '';
                      String studentId =
                          studentDetails?['id']?.toString() ?? '';
                      Get.to(
                        () => StudentComplaintView(
                          academyId: academyId,
                          studentId: studentId,
                          studentName: widget.studentName,
                          className: widget.className,
                          roll: widget.roll,
                          academyName: widget.academyName,
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(
                      thickness: 1,
                      color: AppTheme.borderOf(context),
                    ),
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.settings_outlined,
                      color: Colors.blueGrey,
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
                    leading: const Icon(
                      Icons.feedback_outlined,
                      color: Colors.amber,
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
                    leading: const Icon(Icons.privacy_tip, color: Colors.teal),
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
                    leading: const Icon(
                      Icons.share_outlined,
                      color: Colors.indigo,
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: AppTheme.tileOf(context, Colors.red),
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  'লগআউট করুন',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showLogoutDialog();
                },
              ),
            ),
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
      body: Stack(
        children: [
          hasError
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 60,
                          color: AppTheme.mutedOf(context),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'ইন্টারনেট কানেকশন নেই অথবা ডাটা লোড করতে সমস্যা হচ্ছে।',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.mutedOf(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: fetchAllData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('পুনরায় চেষ্টা করুন'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchAllData,
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceOf(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.borderOf(context),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withValues(alpha: 0.12),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                initiallyExpanded: false,
                                tilePadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AppTheme.tileOf(
                                    context,
                                    Colors.indigo,
                                  ),
                                  backgroundImage:
                                      (profileImageUrl != null &&
                                          profileImageUrl.isNotEmpty)
                                      ? NetworkImage(profileImageUrl)
                                      : null,
                                  child:
                                      (profileImageUrl == null ||
                                          profileImageUrl.isEmpty)
                                      ? Text(
                                          widget.studentName.isNotEmpty
                                              ? widget.studentName[0]
                                              : 'S',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.studentName,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.inkOf(context),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: isPresent
                                            ? Colors.green
                                            : Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _todayAttendanceStatus,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isPresent
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: EdgeInsets.only(top: 4.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.academyName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.mutedOf(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.tileOf(
                                                context,
                                                Colors.indigo,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'শ্রেণি: ${widget.className}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.indigo,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.tileOf(
                                                context,
                                                Colors.orange,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'রোল: ${widget.roll}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Divider(height: 20, thickness: 1),
                                        const Text(
                                          'অন্যান্য ব্যক্তিগত তথ্য',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        _buildAnimatedDetailRow(
                                          Icons.person_outline,
                                          'বাবার নাম',
                                          studentDetails?['father_name'] ??
                                              'তথ্য নেই',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildAnimatedDetailRow(
                                          Icons.phone_outlined,
                                          'মোবাইল নম্বর',
                                          studentDetails?['phone'] ??
                                              'তথ্য নেই',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildAnimatedDetailRow(
                                          Icons.location_on_outlined,
                                          'ঠিকানা',
                                          studentDetails?['address'] ??
                                              'তথ্য নেই',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildAnimatedDetailRow(
                                          Icons.account_balance_wallet_outlined,
                                          'মাসিক ফি',
                                          studentDetails?['monthly_fee'] != null
                                              ? '${studentDetails!['monthly_fee']} টাকা'
                                              : 'তথ্য নেই',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 25),
                        Text(
                          'একাডেমিক কার্যক্রম',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.inkOf(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'মডেল টেস্ট',
                                icon: Icons.quiz_rounded,
                                color: Colors.pink,
                                onTap: () {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  String studentId =
                                      studentDetails?['id']?.toString() ?? '';

                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentModelTestView(
                                          academyId: academyId,
                                          className: widget.className,
                                          studentId: studentId,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'উপস্থিতি',
                                icon: Icons.calendar_today_rounded,
                                color: Colors.teal,
                                onTap: () {
                                  String studentId =
                                      studentDetails?['id']?.toString() ?? '';
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentAttendanceView(
                                          studentId: studentId,
                                          studentName: widget.studentName,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'বেতন হিসাব',
                                icon: Icons.account_balance_wallet_rounded,
                                color: Colors.green,
                                onTap: () {
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      _navigateToFeeDetailsPage();
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'শিক্ষকগণ',
                                icon: Icons.supervisor_account_rounded,
                                color: Colors.purple,
                                onTap: () {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentTeachersView(
                                          academyId: academyId,
                                          academyName: widget.academyName,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'সিলেবাস',
                                icon: Icons.menu_book_rounded,
                                color: Colors.purple,
                                onTap: () {
                                  AdService.showAdWithTracking(
                                    onComplete: () async {
                                      String academyId =
                                          studentDetails?['academy_id'] ?? '';
                                      String className = widget.className
                                          .trim();

                                      if (academyId.isEmpty ||
                                          className.isEmpty) {
                                        Get.snackbar(
                                          "ত্রুটি",
                                          "প্রতিষ্ঠান বা ক্লাসের তথ্য পাওয়া যায়নি!",
                                          backgroundColor: Colors.red,
                                          colorText: Colors.white,
                                        );
                                        return;
                                      }

                                      try {
                                        final response = await Supabase
                                            .instance
                                            .client
                                            .from('syllabus_files')
                                            .select('file_url')
                                            .eq('academy_id', academyId)
                                            .eq('class_name', className)
                                            .order(
                                              'created_at',
                                              ascending: false,
                                            )
                                            .limit(1);

                                        if ((response as List).isNotEmpty) {
                                          String fileUrl =
                                              response[0]['file_url'] ?? '';

                                          if (fileUrl.isNotEmpty) {
                                            final Uri uri = Uri.parse(fileUrl);

                                            if (await launchUrl(
                                              uri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            )) {
                                              // Success
                                            } else {
                                              Get.snackbar(
                                                "ত্রুটি",
                                                "ফাইলটি ওপেন করা সম্ভব হচ্ছে না!",
                                                backgroundColor: Colors.red,
                                                colorText: Colors.white,
                                              );
                                            }
                                          } else {
                                            Get.snackbar(
                                              "দুঃখিত",
                                              "ফাইলের লিংক পাওয়া যায়নি।",
                                              backgroundColor: Colors.orange,
                                              colorText: Colors.white,
                                            );
                                          }
                                        } else {
                                          Get.snackbar(
                                            "তথ্য নেই",
                                            "আপনার ক্লাসের জন্য কোনো সিলেবাস আপলোড করা হয়নি।",
                                            backgroundColor: Colors.orange,
                                            colorText: Colors.white,
                                          );
                                        }
                                      } catch (e) {
                                        Get.snackbar(
                                          "ত্রুটি",
                                          "সিলেবাস লোড করতে সমস্যা হয়েছে: $e",
                                          backgroundColor: Colors.red,
                                          colorText: Colors.white,
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'ক্লাশ রুটিন',
                                icon: Icons.schedule_rounded,
                                color: Colors.indigo,
                                onTap: () {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentRoutineView(
                                          academyId: academyId,
                                          className: widget.className,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'অভিযোগ',
                                icon: Icons.report_problem_rounded,
                                color: Colors.redAccent,
                                onTap: () {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  String studentId =
                                      studentDetails?['id']?.toString() ?? '';
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentComplaintView(
                                          academyId: academyId,
                                          studentId: studentId,
                                          studentName: widget.studentName,
                                          className: widget.className,
                                          roll: widget.roll,
                                          academyName: widget.academyName,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'রেজাল্ট দেখুন',
                                icon: Icons.insert_chart_rounded,
                                color: Colors.orange,
                                onTap: () async {
                                  // 🔥 অত্যন্ত সুরক্ষিত উপায়ে একাডেমি আইডি সংগ্রহ করা
                                  String academyId =
                                      studentDetails?['academy_id']
                                          ?.toString() ??
                                      '';

                                  if (academyId.isEmpty) {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    academyId =
                                        prefs.getString('student_academy_id') ??
                                        '';
                                  }

                                  String className = widget.className;
                                  String studentRoll = widget.roll;

                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentResultView(
                                          academyId: academyId,
                                          className: className,
                                          studentRoll: studentRoll,
                                          studentName: widget.studentName,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'পরিক্ষার রুটিন',
                                icon: Icons.school_outlined,
                                color: Colors.indigo,
                                onTap: () {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  AdService.showAdWithTracking(
                                    onComplete: () {
                                      Get.to(
                                        () => StudentExamRoutineView(
                                          academyId: academyId,
                                          className: widget.className,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 25),
                        Text(
                          'সর্বশেষ নোটিশসমূহ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.inkOf(context),
                          ),
                        ),
                        SizedBox(height: 12),
                        noticesList.isEmpty
                            ? Container(
                                padding: EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceOf(context),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.borderOf(context),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withValues(
                                        alpha: 0.08,
                                      ),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    'এই মুহূর্তে কোনো নতুন নোটিশ নেই',
                                    style: TextStyle(
                                      color: AppTheme.mutedOf(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: noticesList.length > 3
                                    ? 3
                                    : noticesList.length,
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final notice = noticesList[index];
                                  return Container(
                                    margin: EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceOf(context),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.borderOf(context),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withValues(
                                            alpha: 0.06,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () =>
                                            _showSingleNoticeDetail(notice),
                                        child: Padding(
                                          padding: EdgeInsets.all(14),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.tileOf(
                                                    context,
                                                    Colors.blue,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.campaign_rounded,
                                                  size: 20,
                                                  color: AppTheme.tileInkOf(
                                                    context,
                                                    Colors.blue,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      notice['title'] ??
                                                          'নোটিশ শিরোনাম নেই',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppTheme.inkOf(
                                                          context,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      notice['description'] ??
                                                          '',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.mutedOf(
                                                          context,
                                                        ),
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        notice['created_at'] !=
                                                                null
                                                            ? notice['created_at']
                                                                  .toString()
                                                                  .substring(
                                                                    0,
                                                                    10,
                                                                  )
                                                            : '',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              AppTheme.mutedOf(
                                                                context,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
          if (isLoading && !hasError)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Colors.indigo,
              ),
            ),
        ],
      ),
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : SizedBox.shrink(),
    );
  }

  Widget _buildAnimatedDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.tileInkOf(context, Colors.indigo)),
        SizedBox(width: 10),
        Text(
          '$title: ',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.mutedOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.inkOf(context),
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    // অনুরোধ অনুযায়ী আপনার দেওয়া অন্যান্য কোনো কোড বা লজিক পরিবর্তন করা হয়নি
    return functionCheck(title, icon, color, onTap);
  }

  Widget functionCheck(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 115,
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.tileOf(context, color),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: AppTheme.tileInkOf(context, color),
              ),
            ),
            SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.inkOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
