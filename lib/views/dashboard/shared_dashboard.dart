import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/app_actions.dart';
import 'package:academy_management/repositories/dashboard_repository.dart';
import 'package:academy_management/views/admin/teachers_view.dart';
import 'package:academy_management/views/admin/super_admin_management_view.dart';
import 'package:academy_management/views/admin/academy_ai_assistant_view.dart';
import 'package:academy_management/views/exams/academy_result_management_view.dart';
import 'package:academy_management/views/finance/total_collected_details_view.dart';
import 'package:academy_management/views/notices/admin_complaints_view.dart';
import 'package:academy_management/views/exams/exam_seat_plan_view.dart';
import 'package:academy_management/views/exams/model_test_view.dart';
import 'package:academy_management/views/finance/other_income_expense_view.dart';
import 'package:academy_management/views/privacy_policy_view.dart';
import 'package:academy_management/views/settings/settings_view.dart';
import 'package:academy_management/views/student/student_id_card_view.dart';
import 'package:academy_management/views/finance/academy_teachers_salary_view.dart';
import 'package:academy_management/views/finance/due_students_pdf_report_view.dart';
import 'package:academy_management/views/finance/financial_pdf_report_view.dart';
import 'package:academy_management/views/exams/admit_card_view.dart';
import 'package:academy_management/views/attendance/attendance_page_view.dart';
import 'package:academy_management/views/exams/class_routine_view.dart';
import 'package:academy_management/views/admin/developer_profile_view.dart';
import 'package:academy_management/views/exams/exam_routine_view.dart';
import 'package:academy_management/views/notices/notice_board_view.dart';
import 'package:academy_management/views/exams/question_create_view.dart';
import 'package:academy_management/views/attendance/student_attendance_page_view.dart';
import 'package:academy_management/views/finance/student_fee_collection_view.dart';
import 'package:academy_management/views/student/class_wise_students_view.dart';
import 'package:academy_management/views/student/students_file_download.dart';
import 'package:academy_management/views/finance/subscription_plan_view.dart';
import 'package:academy_management/views/exams/syllabus_view.dart';
import 'package:academy_management/views/teacher/teacher_home_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/widgets/notification_bell.dart';
import 'package:academy_management/widgets/theme_mode_toggle.dart';
import 'dart:async';
import 'dart:io';
import '../auth/login_view.dart';
import '../student/students_view.dart';

class SharedDashboard extends StatefulWidget {
  final String role;
  final String userName;
  final String? currentUserId; // এখানে যোগ করা হয়েছে
  final String? currentUserName; // এখানে যোগ করা হয়েছে

  const SharedDashboard({
    super.key,
    required this.role,
    required this.userName,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<SharedDashboard> createState() => _SharedDashboardState();
}

class _SharedDashboardState extends State<SharedDashboard> {
  final supabase = Supabase.instance.client;
  late final AppStateController _appState;
  Worker? _languageWorker;

  // Local mirror of the shared language state; kept so the large build method
  // does not need a full Obx rewrite.
  bool _isEnglish = false;

  // রিয়েল-টাইম ডাটা হোল্ড করার জন্য ভেরিয়েবলসমূহ
  Map<String, dynamic> _academyStats = {
    'academyId': null,
    'totalStudents': 0,
    'totalExpectedFee': '৳ ০',
    'totalDue': '৳ ০',
    'totalCollected': '৳ ০',
    'totalRemainingCollection': '৳ ০',
    'dateRange': '',
    'totalTeacherSalary': '৳ ০',
    'paidTeacherSalary': '৳ ০',
    'remainingTeacherSalary': '৳ ০',
    'netBalance': '৳ ০',
    'totalOtherIncome': '৳ ০',
    'totalOtherExpense': '৳ ০',
    'ytdCollected': '৳ ০',
  };

  bool _hasInternetConnection = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    _appState = Get.find<AppStateController>();
    _isEnglish = _appState.isEnglish.value;
    _languageWorker = ever(_appState.isEnglish, (value) {
      if (mounted) setState(() => _isEnglish = value);
    });

    // রোল চেক করে যদি টিচার হয় তবে সরাসরি টিচারের হোমপেজে রিডাইরেক্ট করে দেওয়া
    if (widget.role != 'super_admin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAll(() => TeacherHomeView(userName: widget.userName));
      });
      return;
    }

    _loadStatsInitial();
    _startNoticeWatch();
    // ব্যাকগ্রাউন্ডে রিয়েল-টাইম বা পরিচালনা করার জন্য টাইমার
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchAcademyStatsSilent();
    });
  }

  Future<void> _startNoticeWatch() async {
    final tenant = await _getAcademyIdSafely();
    if (tenant == null || tenant.isEmpty) return;
    final key = _appState.readerKey.value?.isNotEmpty == true
        ? _appState.readerKey.value!
        : (supabase.auth.currentUser?.id ?? '');
    if (key.isEmpty) return;
    _appState.startNoticeWatch(
      academyId: tenant,
      role: 'super_admin',
      readerKey: key,
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _languageWorker?.dispose();
    super.dispose();
  }

  Future<bool> _checkInternet() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> _loadStatsInitial() async {
    bool isConnected = await _checkInternet();
    if (!isConnected) {
      setState(() {
        _hasInternetConnection = false;
      });
      return;
    }

    var stats = await _fetchAcademyStats();
    if (mounted) {
      setState(() {
        _hasInternetConnection = true;
        _academyStats = stats;
      });
    }
  }

  Future<void> _fetchAcademyStatsSilent() async {
    bool isConnected = await _checkInternet();
    if (!isConnected) {
      if (mounted && _hasInternetConnection) {
        setState(() {
          _hasInternetConnection = false;
        });
      }
      return;
    }

    var stats = await _fetchAcademyStats();
    if (mounted) {
      setState(() {
        _hasInternetConnection = true;
        _academyStats = stats;
      });
    }
  }

  /// Aggregated dashboard data now lives in the repository layer.
  Future<Map<String, dynamic>> _fetchAcademyStats() async {
    final stats = await DashboardRepository().fetchStats();
    return stats.toMap();
  }

  Future<String?> _getAcademyIdSafely() =>
      AcademyRepository().currentUserAcademyId();

  /// Opens the admin financial PDF report from either the AppBar or drawer.
  Future<void> _openFinancialReport() async {
    final academyId = await _getAcademyIdSafely();
    if (!mounted) return;
    if (academyId == null || academyId.trim().isEmpty) {
      Get.snackbar(
        _isEnglish ? 'Error' : 'ত্রুটি',
        _isEnglish ? 'Academy ID not found!' : 'একাডেমি আইডি পাওয়া যায়নি!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    await Get.to(() => FinancialPdfReportView(academyId: academyId));
  }

  void _checkAndShowYearTransitionDialog(BuildContext context) {
    int currentYear = DateTime.now().year;
    int targetExpectedYear = 2027;

    if (currentYear < targetExpectedYear) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 28),
                const SizedBox(width: 8),
                Text(
                  _isEnglish ? 'Not Time Yet' : 'সময় হয়নি',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
            content: Text(
              _isEnglish
                  ? '2027 or new academic session has not started yet! (Current year: $currentYear).\n\nThis option is scheduled to be used only after the next year or new session begins.'
                  : 'এখনো ২০২৭ বা নতুন শিক্ষাবর্ষ শুরু হয়নি! (বর্তমান বছর: $currentYear)।\n\n'
                        'এই অপশনটি শুধুমাত্র পরবর্তী বছর বা নতুন শিক্ষাবর্ষ শুরু হওয়ার পর ব্যবহারের জন্য নির্ধারিত।',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: AppTheme.inkOf(context),
                height: 1.4,
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: Text(_isEnglish ? 'Understood' : 'বুঝেছি'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } else {
      _showYearTransitionConfirmationDialog(context);
    }
  }

  void _showYearTransitionConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.teal,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                _isEnglish ? 'Promotion to New Year' : 'নতুন বছরে উন্নীতকরণ',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEnglish
                      ? 'Are you sure you want to transition to the new academic year?'
                      : 'আপনি কি নিশ্চিতভাবে নতুন শিক্ষাবর্ষে রূপান্তর করতে চান?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isEnglish
                      ? '• Current class due accounts of all students will be saved to a separate table (yearly_due_history).\n\n• All students will automatically promote to the next class dynamically according to database sequence.\n\n• Other income-expenses and previous general accounts will remain unchanged and new year calculation will start.'
                      : '• সকল শিক্ষার্থীর বর্তমান ক্লাসের বকেয়া হিসাব আলাদা একটি সংরক্ষণ টেবিলে (yearly_due_history) জমা হয়ে যাবে।\n\n'
                            '• ডাটাবেসের সিকোয়েন্স অনুযায়ী সকল শিক্ষার্থী স্বয়ংক্রিয়ভাবে ডাইনামিক্যালি পরবর্তী ক্লাসে উন্নীত হবে।\n\n'
                            '• অন্যান্য আয়-ব্যয় এবং পূর্বের সাধারণ হিসাবগুলো অপরিবর্তিত থাকবে এবং নতুন বছরের হিসাব শুরু হবে।',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: AppTheme.inkOf(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                _isEnglish ? 'Cancel' : 'বাতিল',
                style: TextStyle(color: AppTheme.mutedOf(context)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _isEnglish ? 'Confirm & Update' : 'কনফার্ম ও আপডেট করুন',
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _executeYearTransition(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeYearTransition(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.teal)),
    );

    try {
      final academyId = await _getAcademyIdSafely();
      if (academyId == null) {
        if (!context.mounted) return;
        Navigator.pop(context);
        Get.snackbar(
          _isEnglish ? "Error" : "ত্রুটি",
          _isEnglish ? "Academy ID not found!" : "একাডেমি আইডি পাওয়া যায়নি!",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final studentResponse = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', academyId);

      final List students = studentResponse as List;
      if (students.isEmpty) {
        if (!context.mounted) return;
        Navigator.pop(context);
        Get.snackbar(
          _isEnglish ? "Warning" : "সতর্কতা",
          _isEnglish ? "No students found!" : "কোনো শিক্ষার্থী পাওয়া যায়নি!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      int currentYear = DateTime.now().year;

      Set<String> uniqueClasses = {};
      for (var student in students) {
        String className =
            student['class']?.toString().trim() ??
            student['class_name']?.toString().trim() ??
            '';
        if (className.isNotEmpty) {
          uniqueClasses.add(className);
        }
      }

      List<String> sortedClasses = uniqueClasses.toList();

      Map<String, String> dynamicClassSequence = {};
      for (int i = 0; i < sortedClasses.length; i++) {
        if (i < sortedClasses.length - 1) {
          dynamicClassSequence[sortedClasses[i]] = sortedClasses[i + 1];
        } else {
          dynamicClassSequence[sortedClasses[i]] = _isEnglish
              ? 'Passed / Alumni'
              : 'উত্তীর্ণ / অ্যালামনাই';
        }
      }

      for (var student in students) {
        String studentId = student['id']?.toString() ?? '';
        String studentName = student['full_name'] ?? student['name'] ?? '';
        String className =
            student['class']?.toString().trim() ??
            student['class_name']?.toString().trim() ??
            '';
        String roll = student['roll']?.toString() ?? '';

        double monthlyFee =
            double.tryParse(student['monthly_fee']?.toString() ?? '0') ?? 0.0;

        await supabase.from('yearly_due_history').insert({
          'academy_id': academyId,
          'student_id': studentId,
          'student_name': studentName,
          'class_name': className,
          'roll': roll,
          'due_amount': monthlyFee,
          'year': currentYear,
        });

        String nextClass = dynamicClassSequence[className] ?? className;

        await supabase
            .from('students')
            .update({'class': nextClass})
            .eq('id', studentId);
      }

      if (!context.mounted) return;
      Navigator.pop(context);
      _loadStatsInitial();

      Get.snackbar(
        _isEnglish ? "Success" : "সফল",
        _isEnglish
            ? "All students' classes have been dynamically updated and previous year dues saved!"
            : "সকল শিক্ষার্থীর ক্লাস ডাইনামিক্যালি আপডেট করা হয়েছে এবং পুরনো বছরের বকেয়া সংরক্ষিত হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      Get.snackbar(
        _isEnglish ? "Error" : "ত্রুটি",
        _isEnglish
            ? "Error while updating: $e"
            : "আপডেট করার সময় সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSuperAdmin = (widget.role == 'super_admin');

    if (!isSuperAdmin) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    final isDark = AppTheme.isDark(context);
    final ink = AppTheme.inkOf(context);
    final border = AppTheme.borderOf(context);
    final appBarIconColor = isDark ? AppTheme.nightInk : Colors.white;

    final data = _academyStats;
    final academyId = data['academyId'];
    int studentCount = data['totalStudents'] ?? 0;
    String totalExpectedFee = data['totalExpectedFee'] ?? '৳ ০';
    String totalDue = data['totalDue'] ?? '৳ ০';
    String totalCollected = data['totalCollected'] ?? '৳ ০';
    String dateRange = data['dateRange'] ?? '';
    String totalTeacherSalary = data['totalTeacherSalary'] ?? '৳ ০';
    String paidTeacherSalary = data['paidTeacherSalary'] ?? '৳ ০';
    String remainingTeacherSalary = data['remainingTeacherSalary'] ?? '৳ ০';
    String netBalance = data['netBalance'] ?? '৳ ০';
    String totalOtherIncome = data['totalOtherIncome'] ?? '৳ ০';
    String totalOtherExpense = data['totalOtherExpense'] ?? '৳ ০';
    String ytdCollected = data['ytdCollected'] ?? '৳ ০';

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(
          isSuperAdmin
              ? (_isEnglish ? 'Admin Panel' : 'অ্যাডমিন প্যানেল')
              : (_isEnglish ? 'Teacher Dashboard' : 'শিক্ষক ড্যাশবোর্ড'),
        ),
        elevation: 0,
        actions: [
          if (isSuperAdmin)
            IconButton(
              icon: Icon(Icons.picture_as_pdf_outlined, color: appBarIconColor),
              tooltip: _isEnglish
                  ? 'Financial Report (PDF)'
                  : 'আর্থিক রিপোর্ট (PDF)',
              onPressed: _openFinancialReport,
            ),
          ThemeModeToggle(color: appBarIconColor),
          NotificationBell(
            color: appBarIconColor,
            onTap: () async {
              final tenant = await _getAcademyIdSafely();
              if (tenant != null && tenant.isNotEmpty) {
                Get.to(
                  () => NoticeBoardView(
                    academyId: tenant,
                    userRole: 'super_admin',
                  ),
                );
              } else {
                Get.snackbar(
                  _isEnglish ? 'Error' : 'ত্রুটি',
                  _isEnglish
                      ? 'Academy ID not found!'
                      : 'একাডেমি আইডি পাওয়া যায়নি!',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
          ),
          if (isSuperAdmin)
            FutureBuilder<int>(
              future: () async {
                final academyId = await _getAcademyIdSafely();
                if (academyId == null) return 0;

                final response = await Supabase.instance.client
                    .from('complaints')
                    .select('id')
                    .eq('academy_id', academyId)
                    .eq('status', 'Pending');

                return (response as List).length;
              }(),
              builder: (context, snapshot) {
                int pendingCount = snapshot.data ?? 0;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.feedback, color: appBarIconColor),
                      tooltip: _isEnglish ? 'Complaints' : 'অভিযোগসমূহ',
                      onPressed: () async {
                        final academyId = await _getAcademyIdSafely();
                        if (academyId != null) {
                          Get.to(
                            () => AdminComplaintsView(academyId: academyId),
                          );
                        } else {
                          Get.snackbar(
                            _isEnglish ? "Error" : "ত্রুটি",
                            _isEnglish
                                ? "Academy ID not found!"
                                : "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                    ),
                    if (pendingCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ড্রয়ারের কাস্টম হেডার (প্রোফাইল + সাবস্ক্রিপশন ইনফো)
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 45, 16, 16),
                    decoration: BoxDecoration(color: Colors.teal),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppTheme.surfaceOf(context),
                              child: Icon(
                                Icons.person,
                                size: 35,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.role.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // সাবস্ক্রিপশন স্ট্যাটাস কার্ড
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'প্ল্যান: প্রিমিয়াম (০০০)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'মেয়াদ শেষ: লাইফটাইম',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: AppTheme.inkOf(context),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 0,
                                  ),
                                  minimumSize: const Size(60, 28),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  Get.to(() => const SubscriptionPlanView());
                                },
                                child: const Text(
                                  'আপগ্রেড',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.system_update_tv_rounded,
                      color: Colors.teal,
                    ),
                    title: Text(
                      _isEnglish
                          ? 'Students List (Excel)'
                          : 'ছাত্রছাত্রীদের তালিকা(এক্সেল)',
                    ),
                    onTap: () async {
                      Navigator.pop(context); // ড্রয়ার বন্ধ করবে
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        Get.to(
                          () => StudentsFileDownloadView(
                            academyId: fetchedAcademyId,
                          ),
                        );
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.teal,
                    ),
                    title: Text(
                      _isEnglish
                          ? 'Financial Report (PDF)'
                          : 'আর্থিক রিপোর্ট (PDF)',
                    ),
                    subtitle: Text(
                      _isEnglish
                          ? 'Generate & saved reports'
                          : 'রিপোর্ট তৈরি ও সংরক্ষিত PDF',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openFinancialReport();
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.update, color: Colors.teal),
                    title: Text(
                      _isEnglish
                          ? 'Update to New Year'
                          : 'নতুন বছরে আপডেট করুন',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _checkAndShowYearTransitionDialog(context);
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: AppTheme.brandOf(context),
                    ),
                    title: Text(_isEnglish ? 'Settings' : 'সেটিংস'),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const SettingsView());
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.feedback, color: Colors.teal),
                    title: Text(_isEnglish ? 'Feedback' : 'ফিডব্যাক'),
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
                    leading: const Icon(Icons.share, color: Colors.teal),
                    title: Text(_isEnglish ? 'Share App' : 'অ্যাপ শেয়ার'),
                    onTap: () {
                      Navigator.pop(context);
                      AppActions.showShareUnavailable();
                    },
                  ),
                  const Divider(),
                  // ডেভেলপারের সাথে যোগাযোগের অপشن (আপডেট করা হয়েছে)
                  ListTile(
                    leading: const Icon(Icons.mail_outline, color: Colors.teal),
                    title: Text(
                      _isEnglish
                          ? 'Contact Developer'
                          : 'ডেভেলপারের সাথে যোগাযোগ',
                    ),
                    onTap: () {
                      Navigator.pop(context); // ড্রয়ার বন্ধ করবে
                      Get.to(
                        () => const DeveloperProfileView(),
                      ); // ডেভেলপার প্রোফাইল পেজে নিয়ে যাবে
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: Text(
                      _isEnglish ? 'Logout' : 'লগআউট',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      await SessionService.signOut();
                      if (mounted) {
                        Get.offAll(() => LoginView());
                      }
                    },
                  ),
                ],
              ),
            ),
            // একেবারে নিচে মাঝখানে শুধু ভার্সন সংখ্যা
            Padding(
              padding: EdgeInsets.only(bottom: 16.0),
              child: Text(
                '1.0.5',
                style: TextStyle(
                  color: AppTheme.mutedOf(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_hasInternetConnection)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off,
                      color: isDark ? Color(0xFFFCA5A5) : Colors.red,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isEnglish
                            ? 'You have no internet connection! Please check your internet connection.'
                            : 'আপনার ইন্টারনেট কানেকশন নেই! দয়া করে ইন্টারনেট সংযোগ চেক করুন।',
                        style: TextStyle(
                          color: isDark
                              ? Color(0xFFFCA5A5)
                              : AppTheme.tileInkOf(context, Colors.red),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              _isEnglish
                  ? 'Academy Financial & General Overview'
                  : 'একাডেমি আর্থিক ও সাধারণ ওভারভিউ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            SizedBox(height: 12),
            Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance,
                            color: AppTheme.brandOf(context),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            _isEnglish
                                ? 'Academy Overall Cash & Balance Calculation'
                                : 'একাডেমির সার্বিক ক্যাশ ও ব্যালেন্স হিসাব',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandOf(context),
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isEnglish
                                ? 'Total Income (Collection + Other):'
                                : 'মোট আয় (বেতন উঠছে + অন্যান্য):',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedOf(context),
                            ),
                          ),
                          Text(
                            '$ytdCollected + $totalOtherIncome',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFF6EE7B7)
                                  : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isEnglish
                                ? 'Total Expense (Teachers Salary + Other):'
                                : 'মোট ব্যয় (শিক্ষকদের বেতন + অন্যান্য):',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedOf(context),
                            ),
                          ),
                          Text(
                            '$paidTeacherSalary + $totalOtherExpense',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFFFCA5A5)
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isEnglish
                                ? 'Net Cash Balance:'
                                : 'নিট ক্যাশ ব্যালেন্স:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: ink,
                            ),
                          ),
                          Text(
                            netBalance,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        if (academyId != null) {
                          await Get.to(
                            () => ClassWiseStudentsView(academyId: academyId),
                          );
                          _loadStatsInitial();
                        } else {
                          Get.snackbar(
                            _isEnglish ? "Error" : "ত্রুটি",
                            _isEnglish
                                ? "Academy ID not found!"
                                : "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        _isEnglish ? 'Total Students' : 'মোট শিক্ষার্থী',
                        _isEnglish
                            ? 'Total: $studentCount\nExpected: $totalExpectedFee'
                            : 'মোটঃ $studentCount জন\nপ্রাপ্যঃ $totalExpectedFee',
                        Icons.groups,
                        Colors.blue,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        if (academyId != null) {
                          await Get.to(
                            () => TotalDueDetailsView(academyId: academyId),
                          );
                          _loadStatsInitial();
                        } else {
                          Get.snackbar(
                            _isEnglish ? "Error" : "ত্রুটি",
                            _isEnglish
                                ? "Academy ID not found!"
                                : "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        _isEnglish ? 'Due (Students)' : 'বকেয়া(ছাত্র-ছাত্রী)',
                        _isEnglish
                            ? 'Total Due: $totalDue\nSalary Due: $studentCount persons'
                            : 'মোট বকেয়া: $totalDue\nবেতন বাকি: $studentCount জনের',
                        Icons.money_off,
                        Colors.redAccent,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        if (academyId != null) {
                          await Get.to(
                            () => TotalCollectedDetailsView(
                              academyId: academyId,
                              dateRange: dateRange,
                            ),
                          );
                          _loadStatsInitial();
                        } else {
                          Get.snackbar(
                            _isEnglish ? "Error" : "ত্রুটি",
                            _isEnglish
                                ? "Academy ID not found!"
                                : "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        _isEnglish ? 'Collected' : 'উঠেছে (সংগৃহীত)',
                        _isEnglish
                            ? 'Collected: $totalCollected\n$dateRange'
                            : 'উঠেছে: $totalCollected\n$dateRange',
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        if (academyId != null) {
                          await Get.to(
                            () => AcademyTeachersSalaryView(
                              academyId: academyId,
                              isReadOnly: true,
                            ),
                          );
                          _loadStatsInitial();
                        } else {
                          Get.snackbar(
                            _isEnglish ? "Error" : "ত্রুটি",
                            _isEnglish
                                ? "Academy ID not found!"
                                : "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        _isEnglish ? 'Salary Payment' : 'বেতন প্রদান',
                        _isEnglish
                            ? 'Monthly Total: $totalTeacherSalary\nRemaining: $remainingTeacherSalary'
                            : 'মাসিক মোট: $totalTeacherSalary\nবাকি প্রাপ্য: $remainingTeacherSalary',
                        Icons.payments,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              _isEnglish
                  ? 'Academy Management & Update'
                  : 'একাডেমি ম্যানেজমেন্ট ও আপডেট',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                _buildDashboardCard(
                  icon: Icons.people_alt_rounded,
                  title: _isEnglish ? 'Students List' : 'ছাত্র-ছাত্রী তালিকা',
                  color: AppTheme.tileOf(context, Colors.teal),
                  iconColor: AppTheme.tileInkOf(context, Colors.teal),
                  onTap: () async {
                    await Get.to(() => StudentsView(userRole: widget.role));
                    _loadStatsInitial();
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.payment_rounded,
                  title: _isEnglish ? 'Fee Collection' : 'বেতন ও ফি সংগ্রহ',
                  color: AppTheme.tileOf(context, Colors.indigo),
                  iconColor: AppTheme.tileInkOf(context, Colors.indigo),
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();

                    if (fetchedAcademyId != null) {
                      await Get.to(
                        () => StudentFeeCollectionPage(
                          academyId: fetchedAcademyId,
                        ),
                      );
                      _loadStatsInitial();
                    } else {
                      Get.snackbar(
                        _isEnglish ? "Error" : "ত্রুটি",
                        _isEnglish
                            ? "Academy ID not found!"
                            : "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.checklist_rounded,
                  title: _isEnglish
                      ? 'Teacher Attendance'
                      : 'উপস্থিতি (শিক্ষক)',
                  color: AppTheme.tileOf(context, Colors.amber),
                  iconColor: AppTheme.tileInkOf(context, Colors.amber),
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();

                    if (fetchedAcademyId != null) {
                      await Get.to(
                        () => AttendancePageView(
                          academyId: fetchedAcademyId,
                          userRole: widget.role,
                        ),
                      );
                      _loadStatsInitial();
                    } else {
                      Get.snackbar(
                        _isEnglish ? "Error" : "ত্রুটি",
                        _isEnglish
                            ? "Academy ID not found!"
                            : "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.assignment_turned_in_rounded,
                  title: _isEnglish ? 'Model Test' : 'মডেল টেস্ট',
                  color: AppTheme.tileOf(context, Colors.brown),
                  iconColor: AppTheme.tileInkOf(context, Colors.brown),
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();
                    if (fetchedAcademyId != null) {
                      await Get.to(
                        () => ModelTestView(
                          academyId: fetchedAcademyId,
                          currentUserId: widget.currentUserId,
                          currentUserName: widget.currentUserName,
                        ),
                      );
                      _loadStatsInitial();
                    } else {
                      Get.snackbar(
                        _isEnglish ? "Error" : "ত্রুটি",
                        _isEnglish
                            ? "Academy ID not found!"
                            : "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.campaign_rounded,
                    title: _isEnglish ? 'Notice Board' : 'নোটিশ বোর্ড',
                    color: AppTheme.tileOf(context, Colors.pink),
                    iconColor: AppTheme.tileInkOf(context, Colors.pink),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => NoticeBoardView(
                            academyId: fetchedAcademyId,
                            userRole: widget.role,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                _buildDashboardCard(
                  icon: Icons.checklist_rounded,
                  title: _isEnglish
                      ? 'Student Attendance'
                      : 'ছাত্র-ছাত্রীদের হাজিরা',
                  color: AppTheme.tileOf(context, Colors.green),
                  iconColor: AppTheme.tileInkOf(context, Colors.green),
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();

                    if (fetchedAcademyId != null) {
                      await Get.to(
                        () => StudentAttendancePageView(
                          academyId: fetchedAcademyId,
                          teacherName: widget.userName,
                        ),
                      );
                      _loadStatsInitial();
                    } else {
                      Get.snackbar(
                        _isEnglish ? "Error" : "ত্রুটি",
                        _isEnglish
                            ? "Academy ID not found!"
                            : "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                // এরর ঠিক করা হয়েছে: academyId ডায়নামিক্যালি ফেচ করে পাস করা হয়েছে
                _buildDashboardCard(
                  icon: Icons.note_alt_rounded,
                  title: _isEnglish ? 'Exam Result' : 'পরীক্ষার রেজাল্ট',
                  color: AppTheme.tileOf(context, Colors.purple),
                  iconColor: AppTheme.tileInkOf(context, Colors.purple),
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();
                    if (fetchedAcademyId != null) {
                      Get.to(
                        () => AcademyResultManagementView(
                          academyId: fetchedAcademyId,
                          currentUserId: widget.currentUserId,
                          currentUserName: widget.currentUserName,
                        ),
                      );
                    } else {
                      Get.snackbar(
                        _isEnglish ? "Error" : "ত্রুটি",
                        _isEnglish
                            ? "Academy ID not found!"
                            : "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: _isEnglish ? 'Add Teacher' : 'নতুন শিক্ষক যোগ',
                    color: AppTheme.tileOf(context, Colors.cyan),
                    iconColor: AppTheme.tileInkOf(context, Colors.cyan),
                    onTap: () async {
                      await Get.to(
                        () => TeachersView(adminUserName: widget.userName),
                      );
                      _loadStatsInitial();
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.manage_accounts_rounded,
                    title: _isEnglish ? 'Staff & Roles' : 'কর্মচারী ও রোল',
                    color: AppTheme.tileOf(context, Colors.indigo),
                    iconColor: AppTheme.tileInkOf(context, Colors.indigo),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => SuperAdminManagementView(
                            academyId: fetchedAcademyId,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.account_balance_wallet_rounded,
                    title: _isEnglish
                        ? 'Income / Expense'
                        : 'অন্যান্য আয় ব্যয়',
                    color: AppTheme.tileOf(context, Colors.blueGrey),
                    iconColor: AppTheme.tileInkOf(context, Colors.blueGrey),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => OtherIncomeExpenseView(
                            academyId: fetchedAcademyId,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.badge_rounded,
                    title: _isEnglish ? 'ID Card' : 'আইডি কার্ড',
                    color: AppTheme.tileOf(context, Colors.deepOrange),
                    iconColor: AppTheme.tileInkOf(context, Colors.deepOrange),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => StudentIdCardView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.schedule_rounded,
                    title: _isEnglish ? 'Class Routine' : 'ক্লাশ রুটিন',
                    color: AppTheme.tileOf(context, Colors.blue),
                    iconColor: AppTheme.tileInkOf(context, Colors.blue),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => ClassRoutineView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.payments_rounded,
                    title: _isEnglish ? 'Academy Salary' : 'প্রতিষ্ঠানের বেতন',
                    color: AppTheme.tileOf(context, Colors.orange),
                    iconColor: AppTheme.tileInkOf(context, Colors.orange),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => AcademyTeachersSalaryView(
                            academyId: fetchedAcademyId,
                            isReadOnly: false,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.card_membership_rounded,
                    title: _isEnglish ? 'Admit Card' : 'এডমিট কার্ড',
                    color: AppTheme.tileOf(context, Colors.amber),
                    iconColor: AppTheme.tileInkOf(context, Colors.amber),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => AdmitCardView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.event_note_rounded,
                    title: _isEnglish ? 'Exam Routine' : 'পরীক্ষার রুটিন',
                    color: AppTheme.tileOf(context, Colors.teal),
                    iconColor: AppTheme.tileInkOf(context, Colors.teal),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => ExamRoutineView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.quiz_rounded,
                    title: _isEnglish ? 'Question Create' : 'প্রশ্ন তৈরি',
                    color: AppTheme.tileOf(context, Colors.deepPurple),
                    iconColor: AppTheme.tileInkOf(context, Colors.deepPurple),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      final currentUserId = supabase.auth.currentUser?.id ?? '';

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => QuestionCreateView(
                            academyId: fetchedAcademyId,
                            currentUserId: currentUserId,
                            currentUserName: widget.userName,
                            userRole: widget.role,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.merge_outlined,
                    title: _isEnglish ? 'Syllabus Create' : 'সিলেবাস তৈরি',
                    color: AppTheme.tileOf(context, Colors.deepPurple),
                    iconColor: AppTheme.tileInkOf(context, Colors.teal),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => SyllabusView(
                            academyId: fetchedAcademyId,
                            userRole: widget.role,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.filter_4_rounded,
                    title: _isEnglish
                        ? 'Seat Number Create'
                        : 'সিট নাম্বার তৈরি',
                    color: AppTheme.tileOf(context, Colors.deepPurple),
                    iconColor: AppTheme.tileInkOf(context, Colors.teal),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => ExamSeatPlanView(
                            academyId: fetchedAcademyId,
                            //userRole: widget.role,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.assistant_rounded,
                    title: _isEnglish ? 'AI Assistant' : 'AI Assistant',
                    color: AppTheme.tileOf(context, Colors.lightBlue),
                    iconColor: AppTheme.tileInkOf(context, Colors.lightBlue),
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => AcademyAiAssistantView(
                            academyId: fetchedAcademyId,
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          _isEnglish ? "Error" : "ত্রুটি",
                          _isEnglish
                              ? "Academy ID not found!"
                              : "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
              ],
            ),
            SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final accentInk = AppTheme.tileInkOf(context, color);
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderOf(context), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedOf(context),
                  ),
                ),
              ),
              Icon(icon, color: accentInk, size: 22),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: accentInk,
              fontFeatures: AppTheme.numericFeatures,
              height: 1.25,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color color,
    required Color iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withValues(alpha: 0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 26, color: iconColor),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TotalDueDetailsView extends StatefulWidget {
  final String academyId;

  const TotalDueDetailsView({super.key, required this.academyId});

  @override
  State<TotalDueDetailsView> createState() => _TotalDueDetailsViewState();
}

class _TotalDueDetailsViewState extends State<TotalDueDetailsView> {
  String selectedClass = 'সব ক্লাস';

  Future<Map<String, List<Map<String, dynamic>>>>
  _fetchGroupedDueStudents() async {
    final supabase = Supabase.instance.client;

    final studentsResponse = await supabase
        .from('students')
        .select('*')
        .eq('academy_id', widget.academyId);

    final now = DateTime.now();
    final List<String> months = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    final currentMonthName = months[now.month - 1];
    final currentMonthWithYear = '$currentMonthName ${now.year}';

    final feeHistoryResponse = await supabase
        .from('student_fee_history')
        .select('student_id, amount, month')
        .eq('academy_id', widget.academyId);

    Map<String, double> paidMap = {};

    for (var item in (feeHistoryResponse as List)) {
      String sId = item['student_id']?.toString() ?? '';
      double amt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
      String dbMonth = item['month']?.toString().trim() ?? '';

      final cleanDbMonth = dbMonth.replaceAll(' ', '');
      final target1 = currentMonthName.replaceAll(' ', '');
      final target2 = currentMonthWithYear.replaceAll(' ', '');

      if (cleanDbMonth.contains(target1) || cleanDbMonth.contains(target2)) {
        paidMap[sId] = (paidMap[sId] ?? 0.0) + amt;
      }
    }

    Map<String, List<Map<String, dynamic>>> groupedByClass = {};
    List<Map<String, dynamic>> allDueList = [];

    for (var student in (studentsResponse as List)) {
      String sId = student['id']?.toString() ?? '';
      double expectedFee =
          double.tryParse(student['monthly_fee']?.toString() ?? '0') ?? 0.0;
      double paidFee = paidMap[sId] ?? 0.0;
      double dueAmount = expectedFee - paidFee;

      if (dueAmount > 0) {
        String className =
            student['class'] ?? student['class_name'] ?? 'অন্যান্য ক্লাস';

        var mutableStudent = Map<String, dynamic>.from(student);
        mutableStudent['due_amount'] = dueAmount;
        mutableStudent['due_month'] = currentMonthName;

        groupedByClass.putIfAbsent(className, () => []).add(mutableStudent);
        allDueList.add(mutableStudent);
      }
    }

    groupedByClass['সব ক্লাস'] = allDueList;
    return groupedByClass;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('বকেয়া শিক্ষার্থীদের তালিকা'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'বকেয়া শিক্ষার্থী PDF রিপোর্ট',
            onPressed: () {
              Get.to(
                () => DueStudentsPdfReportView(academyId: widget.academyId),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _fetchGroupedDueStudents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('ত্রুটি: ${snapshot.error}'));
          }

          final groupedData = snapshot.data ?? {};
          if (groupedData.isEmpty || (groupedData['সব ক্লাস'] ?? []).isEmpty) {
            return Center(
              child: Text(
                'চলতি মাসে কোনো বকেয়া নেই! সবাই ফি পরিশোধ করেছে।',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.isDark(context)
                      ? Color(0xFF6EE7B7)
                      : AppTheme.tileInkOf(context, Colors.green),
                ),
              ),
            );
          }

          List<String> classes = groupedData.keys.toList();
          classes.remove('সব ক্লাস');
          classes.sort();
          classes.insert(0, 'সব ক্লাস');

          if (!classes.contains(selectedClass)) {
            selectedClass = 'সব ক্লাস';
          }

          List<Map<String, dynamic>> currentStudents =
              groupedData[selectedClass] ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 55,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    String className = classes[index];
                    bool isSelected = (className == selectedClass);
                    int count = groupedData[className]?.length ?? 0;

                    return Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('$className ($count)'),
                        selected: isSelected,
                        selectedColor: Colors.redAccent,
                        backgroundColor: AppTheme.altSurfaceOf(context),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppTheme.inkOf(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        onSelected: (bool selected) {
                          setState(() {
                            selectedClass = className;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: currentStudents.isEmpty
                    ? Center(
                        child: Text(
                          'এই ক্লাসে কোনো বকেয়া শিক্ষার্থী নেই।',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: currentStudents.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          final student = currentStudents[index];
                          String studentName =
                              student['full_name'] ??
                              student['name'] ??
                              'নামহীন শিক্ষার্থী';
                          String fatherName =
                              student['father_name'] ??
                              student['guardian_name'] ??
                              'পাওয়া যায়নি';
                          String roll = student['roll']?.toString() ?? 'নেই';
                          String className =
                              student['class'] ??
                              student['class_name'] ??
                              'প্রযোজ্য নয়';
                          String dueMonth = student['due_month'] ?? 'চলতি মাস';
                          double dueAmount = student['due_amount'] ?? 0.0;

                          return Card(
                            elevation: 2,
                            margin: EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.tileOf(
                                      context,
                                      Colors.redAccent,
                                    ),
                                    backgroundImage:
                                        (student['image_url'] != null &&
                                            student['image_url']
                                                .toString()
                                                .isNotEmpty)
                                        ? NetworkImage(student['image_url'])
                                        : null,
                                    child:
                                        (student['image_url'] == null ||
                                            student['image_url']
                                                .toString()
                                                .isEmpty)
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.red,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          studentName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontSize: 15,
                                                color: AppTheme.inkOf(context),
                                              ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'বাবার নাম: $fatherName',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontSize: 12,
                                                color: AppTheme.mutedOf(
                                                  context,
                                                ),
                                              ),
                                        ),
                                        SizedBox(height: 4),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              'ক্লাস: $className',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.tileInkOf(
                                                  context,
                                                  Colors.blue,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              'রোল: $roll',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.mutedOf(
                                                  context,
                                                ),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.tileOf(
                                                  context,
                                                  Colors.orange,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'মাস: $dueMonth',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.tileInkOf(
                                                    context,
                                                    Colors.orange,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '৳ ${dueAmount.toStringAsFixed(0)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: AppTheme.isDark(context)
                                              ? Color(0xFFFCA5A5)
                                              : Colors.red.shade700,
                                          fontFeatures:
                                              AppTheme.numericFeatures,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
