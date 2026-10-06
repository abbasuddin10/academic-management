import 'package:academy_management/views/admin/teachers_view.dart';
import 'package:academy_management/views/dashboard/Model_Test_View.dart';
import 'package:academy_management/views/dashboard/OtherIncomeExpenseView.dart';
import 'package:academy_management/views/dashboard/StudentIdCardVie.dart';
import 'package:academy_management/views/dashboard/academy_teachers_salary_view.dart';
import 'package:academy_management/views/dashboard/admit_card_view.dart';
import 'package:academy_management/views/dashboard/attendance_page_view.dart';
import 'package:academy_management/views/dashboard/class_routine_view.dart';
import 'package:academy_management/views/dashboard/exam_routine_view.dart';
import 'package:academy_management/views/dashboard/notice_board_view.dart';
import 'package:academy_management/views/dashboard/question_create_view.dart';
import 'package:academy_management/views/dashboard/student_attendance_page_view.dart';
import 'package:academy_management/views/dashboard/student_fee_collection_view.dart';
import 'package:academy_management/views/dashboard/teacher_home_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../auth/login_view.dart';
import '../student/students_view.dart';
import 'class_wise_students_view.dart';
import 'total_collected_details_view.dart';

class SharedDashboard extends StatefulWidget {
  final String role;
  final String userName;

  const SharedDashboard({
    super.key,
    required this.role,
    required this.userName,
  });

  @override
  State<SharedDashboard> createState() => _SharedDashboardState();
}

class _SharedDashboardState extends State<SharedDashboard> {
  final supabase = Supabase.instance.client;

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
  int _unreadNoticeCount = 0; // সিন/আনসিন নোটিফিকেশন সংখ্যা ট্র্যাক করার জন্য

  @override
  void initState() {
    super.initState();

    // রোল চেক করে যদি টিচার হয় তবে সরাসরি টিচারের হোমপেজে রিডাইরেক্ট করে দেওয়া
    if (widget.role != 'super_admin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // আপনার তৈরি করা টিচারের হোমপেজ এখানে যুক্ত হবে।
        Get.offAll(() => TeacherHomeView(userName: widget.userName));
      });
      return;
    }

    _loadStatsInitial();
    // ব্যাকগ্রাউন্ডে রিয়েল-টাইম বা পরিচালনা করার জন্য টাইমার
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchAcademyStatsSilent();
      _fetchUnreadNoticeCount(); // রিয়েল-টাইমে নোটিফিকেশন সংখ্যা চেক করা
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<bool> _checkInternet() async {
    // ফ্লাটার ওয়েব বা ব্রাউজারের ক্ষেত্রে ডার্ট আইও-এর ইন্টারনেট লুকআপ কাজ করে না,
    // তাই ওয়েবের ক্ষেত্রে সরাসরি true রিটার্ন করা নিরাপদ।
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
    await _fetchUnreadNoticeCount();
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

  // আনসিন নোটিফিকেশন সংখ্যা ফেচ করার ফাংশন
  Future<void> _fetchUnreadNoticeCount() async {
    try {
      final academyId = await _getAcademyIdSafely();
      if (academyId == null) return;

      final currentUserEmail = supabase.auth.currentUser?.email;

      // নোটিশ টেবিল থেকে মোট নোটিশ অথবা ইউজারের স্ট্যাটাস চেক করে আনসিন সংখ্যা বের করা
      final response = await supabase
          .from('notices')
          .select('id')
          .eq('academy_id', academyId);

      if (response != null && mounted) {
        // যদি আপনার ডাটাবেসে রিড/আনসিন ট্র্যাক করার আলাদা ফিল্ড বা লজিক থাকে তা এখানে কাজ করবে,
        // আপাতত সামগ্রিক নোটিশ কাউন্ট বা আনসিন কাউন্ট দেখানো হলো
        setState(() {
          _unreadNoticeCount = (response as List).length;
        });
      }
    } catch (e) {
      // সাইಲೆಂ্ট ক্যাচ
    }
  }

  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  // নিরাপদভাবে বর্তমান ইউজারের ইমেইল দিয়ে একাডেমি ডেটা ও আইডি ফেচ করার ফাংশন
  Future<Map<String, dynamic>> _fetchAcademyStats() async {
    try {
      final currentUserEmail = supabase.auth.currentUser?.email;
      if (currentUserEmail == null) {
        return _emptyStats();
      }

      final responseUser = await supabase
          .from('users')
          .select('academy_id')
          .eq('email', currentUserEmail)
          .limit(1);

      if (responseUser == null ||
          (responseUser as List).isEmpty ||
          responseUser[0]['academy_id'] == null) {
        return _emptyStats();
      }

      final academyId = responseUser[0]['academy_id'];

      final studentResponse = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', academyId);

      final List studentsList = studentResponse as List;
      final int totalStudentsCount = studentsList.length;

      double totalFeeSum = 0.0;
      for (var student in studentsList) {
        double fee =
            double.tryParse(student['monthly_fee']?.toString() ?? '0') ?? 0.0;
        totalFeeSum += fee;
      }

      // শিক্ষক তালিকার জন্য query (বেতন এবং যোগদানের তারিখ সহ)
      final teacherResponse = await supabase
          .from('users')
          .select('salary, created_at')
          .eq('academy_id', academyId)
          .inFilter('role', ['teacher', 'super_admin']);

      final List teachersList = teacherResponse as List;

      double totalOneMonthSalarySum = 0.0;
      double totalAccruedSalarySinceJoining = 0.0;

      final now = DateTime.now();

      for (var teacher in teachersList) {
        double monthlySal =
            double.tryParse(teacher['salary']?.toString() ?? '0') ?? 0.0;
        totalOneMonthSalarySum += monthlySal;

        final createdAtStr = teacher['created_at']?.toString();
        if (createdAtStr != null) {
          DateTime? createdAt = DateTime.tryParse(createdAtStr);
          if (createdAt != null) {
            DateTime localJoinDate = createdAt.toLocal();

            int totalMonths =
                (now.year - localJoinDate.year) * 12 +
                now.month -
                localJoinDate.month;
            if (totalMonths < 0) totalMonths = 0;

            double teacherTotalDue = monthlySal * (totalMonths + 1);
            totalAccruedSalarySinceJoining += teacherTotalDue;
          } else {
            totalAccruedSalarySinceJoining += monthlySal;
          }
        } else {
          totalAccruedSalarySinceJoining += monthlySal;
        }
      }

      final salaryHistoryResponse = await supabase
          .from('teacher_salary_history')
          .select('amount')
          .eq('academy_id', academyId);

      double paidSalarySum = 0.0;
      if (salaryHistoryResponse != null) {
        for (var item in (salaryHistoryResponse as List)) {
          double amt =
              double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
          paidSalarySum += amt;
        }
      }

      double remainingSalary = totalAccruedSalarySinceJoining - paidSalarySum;
      if (remainingSalary < 0) remainingSalary = 0;

      final List<String> months = [
        'জানুয়ারি',
        'ফেব্রুয়ারি',
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

      DateTime startDate;
      DateTime endDate = DateTime(now.year, now.month, 10, 23, 59, 59);

      int prevMonth = now.month - 1;
      int prevYear = now.year;
      if (prevMonth == 0) {
        prevMonth = 12;
        prevYear -= 1;
      }
      startDate = DateTime(prevYear, prevMonth, 10, 0, 0, 0);

      String customDateRangeText =
          '${startDate.day} ${months[startDate.month - 1]} থেকে ${endDate.day} ${months[endDate.month - 1]}';

      final feeHistoryResponse = await supabase
          .from('student_fee_history')
          .select('amount, created_at, month')
          .eq('academy_id', academyId);

      double totalCollectedSum = 0.0;
      if (feeHistoryResponse != null) {
        for (var item in (feeHistoryResponse as List)) {
          final createdAtStr = item['created_at']?.toString();
          if (createdAtStr != null) {
            DateTime? createdAt = DateTime.tryParse(createdAtStr);
            if (createdAt != null) {
              DateTime localCreatedAt = createdAt.toLocal();
              if (localCreatedAt.isAfter(
                    startDate.subtract(const Duration(seconds: 1)),
                  ) &&
                  localCreatedAt.isBefore(
                    endDate.add(const Duration(seconds: 1)),
                  )) {
                double amt =
                    double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                totalCollectedSum += amt;
              }
            }
          }
        }
      }

      double totalYtdCollectedSum = 0.0;
      if (feeHistoryResponse != null) {
        for (var item in (feeHistoryResponse as List)) {
          final createdAtStr = item['created_at']?.toString();
          if (createdAtStr != null) {
            DateTime? createdAt = DateTime.tryParse(createdAtStr);
            if (createdAt != null) {
              DateTime localCreatedAt = createdAt.toLocal();
              if (localCreatedAt.year == now.year &&
                  localCreatedAt.month <= now.month) {
                double amt =
                    double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                totalYtdCollectedSum += amt;
              }
            }
          }
        }
      }

      double totalOtherIncome = 0.0;
      double totalOtherExpense = 0.0;
      try {
        final otherIncomeExpenseResponse = await supabase
            .from('other_income_expenses')
            .select('amount, type, created_at')
            .eq('academy_id', academyId);

        if (otherIncomeExpenseResponse != null) {
          for (var item in (otherIncomeExpenseResponse as List)) {
            final createdAtStr = item['created_at']?.toString();
            bool isCurrentYearAndMonth = true;
            if (createdAtStr != null) {
              DateTime? createdAt = DateTime.tryParse(createdAtStr);
              if (createdAt != null) {
                DateTime localCreatedAt = createdAt.toLocal();
                if (!(localCreatedAt.year == now.year &&
                    localCreatedAt.month <= now.month)) {
                  isCurrentYearAndMonth = false;
                }
              }
            }

            if (isCurrentYearAndMonth) {
              double amt =
                  double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
              String type = item['type']?.toString().toLowerCase().trim() ?? '';
              if (type == 'income' || type == 'آئ' || type == 'আয়') {
                totalOtherIncome += amt;
              } else if (type == 'expense' ||
                  type == 'ব্যয়' ||
                  type == 'cost') {
                totalOtherExpense += amt;
              }
            }
          }
        }
      } catch (e) {}
      // student_other_collections টেবিল থেকে শিক্ষার্থীদের অন্যান্য ফি ফেচ করা
      double studentOtherCollectionsSum = 0.0;
      try {
        final studentOtherResponse = await supabase
            .from('student_other_collections')
            .select('amount, payment_date, created_at')
            .eq('academy_id', academyId);

        if (studentOtherResponse != null) {
          for (var item in (studentOtherResponse as List)) {
            final dateStr =
                item['payment_date'] ?? item['created_at']?.toString();
            bool isCurrentYearAndMonth = true;
            if (dateStr != null) {
              DateTime? createdAt = DateTime.tryParse(dateStr);
              if (createdAt != null) {
                DateTime localCreatedAt = createdAt.toLocal();
                // চলতি বছর এবং চলতি মাস বা তার আগের মাসগুলোর ফিল্টার (ytdCollected এর সাথে মিল রেখে)
                if (!(localCreatedAt.year == now.year &&
                    localCreatedAt.month <= now.month)) {
                  isCurrentYearAndMonth = false;
                }
              }
            }

            if (isCurrentYearAndMonth) {
              double amt =
                  double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
              studentOtherCollectionsSum += amt;
            }
          }
        }
      } catch (e) {
        // সাইಲೆಂ্ট ক্যাচ
      }

      // অন্যান্য আয় এবং শিক্ষার্থীদের অন্যান্য কালেকশন একসাথে যোগ করা
      double finalTotalOtherIncome =
          totalOtherIncome + studentOtherCollectionsSum;

      double grandTotalIncome = totalYtdCollectedSum + finalTotalOtherIncome;
      double grandTotalExpense = paidSalarySum + totalOtherExpense;
      double netBalance = grandTotalIncome - grandTotalExpense;

      double totalDueSum = totalFeeSum - totalCollectedSum;
      if (totalDueSum < 0) totalDueSum = 0;

      double totalRemainingCollection = totalFeeSum - totalCollectedSum;
      if (totalRemainingCollection < 0) totalRemainingCollection = 0;

      return {
        'academyId': academyId,
        'totalStudents': totalStudentsCount,
        'totalExpectedFee': '৳ ${totalFeeSum.toStringAsFixed(0)}',
        'totalDue': '৳ ${totalDueSum.toStringAsFixed(0)}',
        'totalCollected': '৳ ${totalCollectedSum.toStringAsFixed(0)}',
        'totalRemainingCollection':
            '৳ ${totalRemainingCollection.toStringAsFixed(0)}',
        'dateRange': customDateRangeText,
        'totalTeacherSalary': '৳ ${totalOneMonthSalarySum.toStringAsFixed(0)}',
        'paidTeacherSalary': '৳ ${paidSalarySum.toStringAsFixed(0)}',
        'remainingTeacherSalary': '৳ ${remainingSalary.toStringAsFixed(0)}',
        'netBalance': '৳ ${netBalance.toStringAsFixed(0)}',
        'totalOtherIncome':
            '৳ ${finalTotalOtherIncome.toStringAsFixed(0)}', // এখানে পরিবর্তন করা হয়েছে
        'totalOtherExpense': '৳ ${totalOtherExpense.toStringAsFixed(0)}',
        'ytdCollected': '৳ ${totalYtdCollectedSum.toStringAsFixed(0)}',
      };
    } catch (e) {
      return _emptyStats();
    }
  }

  Map<String, dynamic> _emptyStats() {
    return {
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
  }

  // হেল্পার ফাংশন: ইমেইল দিয়ে সহজে academy_id বের করার জন্য
  Future<String?> _getAcademyIdSafely() async {
    try {
      final currentUserEmail = supabase.auth.currentUser?.email;
      if (currentUserEmail == null) return null;

      final responseUser = await supabase
          .from('users')
          .select('academy_id')
          .eq('email', currentUserEmail)
          .limit(1);

      if (responseUser != null && (responseUser as List).isNotEmpty) {
        return responseUser[0]['academy_id']?.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ভুলবশত বা আগে ক্লিক করলে ইয়ার ভ্যালিডেশন চেক করার ফাংশন
  void _checkAndShowYearTransitionDialog(BuildContext context) {
    int currentYear = DateTime.now().year; // বর্তমান বছর (যেমন: ২০২৬)
    int targetExpectedYear = 2027; // যে বছর থেকে নতুন ক্লাস শুরু হবে

    // যদি বর্তমান বছর টার্গেট বছরের চেয়ে কম হয়, তবে ওয়ার্নিং দিবে
    if (currentYear < targetExpectedYear) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('সময় হয়নি', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: Text(
              'এখনো ২০২৭ বা নতুন শিক্ষাবর্ষ শুরু হয়নি! (বর্তমান বছর: $currentYear)।\n\n'
              'এই অপশনটি শুধুমাত্র পরবর্তী বছর বা নতুন শিক্ষাবর্ষ শুরু হওয়ার পর ব্যবহারের জন্য নির্ধারিত।',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('বুঝেছি'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } else {
      // বছর মিলে গেলে মূল কনফার্মেশন ডায়ালগ দেখাবে
      _showYearTransitionConfirmationDialog(context);
    }
  }

  // কনফার্মেশন ডায়ালগ দেখানোর ফাংশন
  void _showYearTransitionConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.teal, size: 28),
              SizedBox(width: 8),
              Text('নতুন বছরে উন্নীতকরণ', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'আপনি কি নিশ্চিতভাবে নতুন শিক্ষাবর্ষে রূপান্তর করতে চান?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 10),
                Text(
                  '• সকল শিক্ষার্থীর বর্তমান ক্লাসের বকেয়া হিসাব আলাদা একটি সংরক্ষণ টেবিলে (yearly_due_history) জমা হয়ে যাবে।\n\n'
                  '• ডাটাবেসের সিকোয়েন্স অনুযায়ী সকল শিক্ষার্থী স্বয়ংক্রিয়ভাবে ডাইনামিক্যালি পরবর্তী ক্লাসে উন্নীত হবে।\n\n'
                  '• অন্যান্য আয়-ব্যয় এবং পূর্বের সাধারণ হিসাবগুলো অপরিবর্তিত থাকবে এবং নতুন বছরের হিসাব শুরু হবে।',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('বাতিল', style: TextStyle(color: Colors.grey)),
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
              child: const Text('কনফার্ম ও আপডেট করুন'),
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

  // ডাইনামিক ইয়ার ট্রানজিশন বা অটো-আপডেট এক্সিকিউট করার ফাংশন
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
        Navigator.pop(context);
        Get.snackbar(
          "ত্রুটি",
          "একাডেমি আইডি পাওয়া যায়নি!",
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
        Navigator.pop(context);
        Get.snackbar(
          "সতর্কতা",
          "কোনো শিক্ষার্থী পাওয়া যায়নি!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      int currentYear = DateTime.now().year;

      // ডাটাবেস থেকে পাওয়া ক্লাসগুলোর ডাইনামিক তালিকা তৈরি
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

      // ডাইনামিক নেক্সট ক্লাস ম্যাপ তৈরি
      Map<String, String> dynamicClassSequence = {};
      for (int i = 0; i < sortedClasses.length; i++) {
        if (i < sortedClasses.length - 1) {
          dynamicClassSequence[sortedClasses[i]] = sortedClasses[i + 1];
        } else {
          dynamicClassSequence[sortedClasses[i]] = 'উত্তীর্ণ / অ্যালামনাই';
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

        // পুরনো বছরের বকেয়া সংরক্ষণ টেবিলে সেভ করা
        await supabase.from('yearly_due_history').insert({
          'academy_id': academyId,
          'student_id': studentId,
          'student_name': studentName,
          'class_name': className,
          'roll': roll,
          'due_amount': monthlyFee,
          'year': currentYear,
        });

        // পরবর্তী ক্লাসে আপডেট করা
        String nextClass = dynamicClassSequence[className] ?? className;

        await supabase
            .from('students')
            .update({'class': nextClass})
            .eq('id', studentId);
      }

      Navigator.pop(context);
      _loadStatsInitial();

      Get.snackbar(
        "সফল",
        "সকল শিক্ষার্থীর ক্লাস ডাইনামিক্যালি আপডেট করা হয়েছে এবং পুরনো বছরের বকেয়া সংরক্ষিত হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Navigator.pop(context);
      Get.snackbar(
        "ত্রুটি",
        "আপডেট করার সময় সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSuperAdmin = (widget.role == 'super_admin');

    // যদি সুপার অ্যাডমিন না হয়, তবে বিল্ড মেথডে লোডিং বা এম্পটি কন্টেইনার রিটার্ন করা যেতে পারে
    // কারণ initState-েই রিডাইরেক্ট হ্যান্ডেল করা হয়েছে।
    if (!isSuperAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

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
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(isSuperAdmin ? 'অ্যাডমিন প্যানেল' : 'শিক্ষক ড্যাশবোর্ড'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // অ্যাপবারের নোটিফিকেশন আইকন (সিন/আনসিন ব্যাজ সহ - শিক্ষক বা এডমিন উভয়ের জন্য)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () async {
                  final academyId = await _getAcademyIdSafely();
                  if (academyId != null) {
                    await Get.to(
                      () => NoticeBoardView(
                        academyId: academyId,
                        userRole: widget.role,
                      ),
                    );
                    _fetchUnreadNoticeCount(); // নোটিশ ভিউ থেকে ফিরে আসলে কাউন্ট আপডেট হবে
                  } else {
                    Get.snackbar(
                      "ত্রুটি",
                      "একাডেমি আইডি পাওয়া যায়নি!",
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                    );
                  }
                },
              ),
              if (_unreadNoticeCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$_unreadNoticeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                widget.userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              accountEmail: Text(widget.role.toUpperCase()),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 45, color: Colors.teal),
              ),
              decoration: const BoxDecoration(color: Colors.teal),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Colors.teal),
              title: const Text('হোম ড্যাশবোর্ড'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.campaign, color: Colors.teal),
              title: const Text('নোটিশ বোর্ড'),
              onTap: () async {
                Navigator.pop(context);
                final fetchedAcademyId = await _getAcademyIdSafely();
                if (fetchedAcademyId != null) {
                  Get.to(
                    () => NoticeBoardView(
                      academyId: fetchedAcademyId,
                      userRole: widget.role,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.account_balance_wallet,
                color: Colors.teal,
              ),
              title: const Text('বেতন ও হিসাব'),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            // সাইড ড্রয়ারে নতুন বছরের আপডেট বাটন যুক্ত করা হয়েছে
            ListTile(
              leading: const Icon(Icons.update, color: Colors.teal),
              title: const Text('নতুন বছরে আপডেট (Year Transition)'),
              onTap: () {
                Navigator.pop(context);
                _checkAndShowYearTransitionDialog(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('লগআউট', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Get.offAll(() => const LoginView());
              },
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
            // ইন্টারনেট কানেকশন না থাকলে সতর্কবার্তা ব্যানার
            if (!_hasInternetConnection)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.red, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'আপনার ইন্টারনেট কানেকশন নেই! দয়া করে ইন্টারনেট সংযোগ চেক করুন।',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const Text(
              'একাডেমি আর্থিক ও সাধারণ ওভারভিউ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.teal.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance,
                            color: Colors.teal,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'একাডেমির সার্বিক ক্যাশ ও ব্যালেন্স হিসাব',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'মোট আয় (বেতন উঠছে + অন্যান্য):',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '$ytdCollected + $totalOtherIncome',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'মোট ব্যয় (শিক্ষকদের বেতন + অন্যান্য):',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '$paidTeacherSalary + $totalOtherExpense',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'নিট ক্যাশ ব্যালেন্স:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            netBalance,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
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
                            "ত্রুটি",
                            "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        'মোট শিক্ষার্থী',
                        'মোটঃ $studentCount জন\nপ্রাপ্যঃ $totalExpectedFee',
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
                            "ত্রুটি",
                            "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        'বকেয়া(ছাত্র-ছাত্রী)',
                        'মোট বকেয়া: $totalDue\nবেতন বাকি: $studentCount জনের',
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
                            "ত্রুটি",
                            "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        'উঠেছে (সংগৃহীত)',
                        'উঠেছে: $totalCollected\n$dateRange',
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
                            "ত্রুটি",
                            "একাডেমি আইডি পাওয়া যায়নি!",
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: _buildStatCard(
                        'বেতন প্রদান',
                        'মাসিক মোট: $totalTeacherSalary\nবাকি প্রাপ্য: $remainingTeacherSalary',
                        Icons.payments,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Text(
              'একাডেমি ম্যানেজমেন্ট ও আপডেট',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _buildDashboardCard(
                  icon: Icons.people_alt_rounded,
                  title: 'ছাত্র-ছাত্রী তালিকা',
                  subtitle: 'তালিকা দেখুন ও যোগ করুন',
                  color: Colors.teal.shade50,
                  iconColor: Colors.teal.shade800,
                  onTap: () async {
                    await Get.to(
                      () => StudentsView(userRole: widget.role),
                    ); // অ্যাডমিনের ক্ষেত্রে widget.role ('super_admin') পাস হবে
                    _loadStatsInitial();
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.payment_rounded,
                  title: 'বেতন ও ফি সংগ্রহ',
                  subtitle: 'মাসিক ফি কালেকশন',
                  color: Colors.indigo.shade50,
                  iconColor: Colors.indigo.shade800,
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
                        "ত্রুটি",
                        "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.checklist_rounded,
                  title: 'উপস্থিতি (শিক্ষক)',
                  subtitle: 'দৈনিক হাজিরা নিন',
                  color: Colors.amber.shade50,
                  iconColor: Colors.amber.shade900,
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
                        "ত্রুটি",
                        "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.checklist_rounded,
                  title: 'ছাত্র-ছাত্রীদের হাজিরা',
                  subtitle: 'দৈনিক উপস্থিতি নিন',
                  color: Colors.green.shade50,
                  iconColor: Colors.green.shade800,
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
                        "ত্রুটি",
                        "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.note_alt_rounded,
                  title: 'পরীক্ষার রেজাল্ট',
                  subtitle: 'মার্কস ও গ্রেড আপডেট',
                  color: Colors.purple.shade50,
                  iconColor: Colors.purple.shade800,
                  onTap: () {},
                ), // মডেল টেস্ট কার্ড (সুপার অ্যাডমিন ও শিক্ষক সবার জন্য)
                _buildDashboardCard(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'মডেল টেস্ট',
                  subtitle: 'মডেল টেস্ট পরিচালনা ও খাতা মূল্যায়ন',
                  color: Colors.brown.shade50,
                  iconColor: Colors.brown.shade800,
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();
                    if (fetchedAcademyId != null) {
                      // মডেল টেস্ট পেজে রাউট করা হলো
                      await Get.to(
                        () => ModelTestView(academyId: fetchedAcademyId),
                      );
                      _loadStatsInitial();
                    } else {
                      Get.snackbar(
                        "ত্রুটি",
                        "একাডেমি আইডি পাওয়া যায়নি!",
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  },
                ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.campaign_rounded,
                    title: 'নোটিশ বোর্ড',
                    subtitle: 'গুরুত্বপূর্ণ ঘোষণা',
                    color: Colors.pink.shade50,
                    iconColor: Colors.pink.shade800,
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
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'নতুন শিক্ষক যোগ',
                    subtitle: 'তালিকা ও অ্যাকাউন্ট তৈরি',
                    color: Colors.cyan.shade50,
                    iconColor: Colors.cyan.shade800,
                    onTap: () async {
                      await Get.to(
                        () => TeachersView(adminUserName: widget.userName),
                      );
                      _loadStatsInitial();
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'অন্যান্য আয় ব্যয়',
                    subtitle: 'হিসাব ও বিবরণী দেখুন',
                    color: Colors.blueGrey.shade50,
                    iconColor: Colors.blueGrey.shade800,
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
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.payments_rounded,
                    title: 'প্রতিষ্ঠানের বেতন',
                    subtitle: 'বেতন প্রদান ও ইতিহাস দেখুন',
                    color: Colors.orange.shade50,
                    iconColor: Colors.orange.shade800,
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
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ), // নতুন যোগ করা আইডি কার্ড অপশন
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.badge_rounded,
                    title: 'আইডি কার্ড',
                    subtitle: 'ক্লাস ভিত্তিক প্রিন্ট ও ডাউনলোড',
                    color: Colors.deepOrange.shade50,
                    iconColor: Colors.deepOrange.shade800,
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => StudentIdCardView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ), // ১. ক্লাশ রুটিন কার্ড
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.schedule_rounded,
                    title: 'ক্লাশ রুটিন',
                    subtitle: 'ক্লাসের সময়সূচি দেখুন',
                    color: Colors.blue.shade50,
                    iconColor: Colors.blue.shade800,
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => ClassRoutineView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),

                // ২. এডমিট কার্ড কার্ড
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.card_membership_rounded,
                    title: 'এডমিট কার্ড',
                    subtitle: 'পরীক্ষার এডমিট তৈরি',
                    color: Colors.amber.shade50,
                    iconColor: Colors.amber.shade900,
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => AdmitCardView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),

                // ৩. পরীক্ষার রুটিন কার্ড
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.event_note_rounded,
                    title: 'পরীক্ষার রুটিন',
                    subtitle: 'রুটিন প্রকাশ ও আপডেট',
                    color: Colors.teal.shade50,
                    iconColor: Colors.teal.shade800,
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => ExamRoutineView(academyId: fetchedAcademyId),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                // ৪. প্রশ্ন তৈরি কার্ড
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.quiz_rounded,
                    title: 'প্রশ্ন তৈরি',
                    subtitle: 'প্রশ্নপত্র তৈরি ও প্রিন্ট',
                    color: Colors.deepPurple.shade50,
                    iconColor: Colors.deepPurple.shade800,
                    onTap: () async {
                      final fetchedAcademyId = await _getAcademyIdSafely();
                      final currentUserId =
                          supabase.auth.currentUser?.id ??
                          ''; // বর্তমান ইউজারের আইডি বের করা

                      if (fetchedAcademyId != null) {
                        await Get.to(
                          () => QuestionCreateView(
                            academyId: fetchedAcademyId,
                            currentUserId:
                                currentUserId, // সঠিকভাবে আইডি পাস করা হলো
                            currentUserName: widget.userName,
                            userRole: widget
                                .role, // ড্যাশবোর্ডের widget থেকে নাম পাস করা হলো
                          ),
                        );
                        _loadStatsInitial();
                      } else {
                        Get.snackbar(
                          "ত্রুটি",
                          "একাডেমি আইডি পাওয়া যায়নি!",
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 30),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              Icon(icon, color: color, size: 22),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
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
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
    required Color iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: iconColor.withOpacity(0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: iconColor),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: iconColor.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  maxLines: 1,
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

    if (feeHistoryResponse != null) {
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
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _fetchGroupedDueStudents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('ত্রুটি: ${snapshot.error}'));
          }

          final groupedData = snapshot.data ?? {};
          if (groupedData.isEmpty || (groupedData['সব ক্লাস'] ?? []).isEmpty) {
            return const Center(
              child: Text(
                'চলتی মাসে কোনো বকেয়া নেই! সবাই ফি পরিশোধ করেছে।',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    String className = classes[index];
                    bool isSelected = (className == selectedClass);
                    int count = groupedData[className]?.length ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('$className ($count)'),
                        selected: isSelected,
                        selectedColor: Colors.redAccent,
                        backgroundColor: Colors.grey.shade200,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
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
                    ? const Center(
                        child: Text(
                          'এই ক্লাসে কোনো বকেয়া শিক্ষার্থী নেই।',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
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
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.redAccent.shade100,
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'বাবার নাম: $fatherName',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              'ক্লাস: $className',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue.shade800,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              'রোল: $roll',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade800,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'মাস: $dueMonth',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange.shade900,
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
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
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
