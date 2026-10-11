import 'package:academy_management/views/admin/teachers_view.dart';
import 'package:academy_management/views/dashboard/Academy_Result_Management_View.dart';
import 'package:academy_management/views/dashboard/Admin_Complaints_View.dart';
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
import 'package:academy_management/views/dashboard/syllabus_view.dart';
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

  // ভাষা পরিবর্তনের স্টেট (false = বাংলা, true = ইংরেজি)
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
  int _unreadNoticeCount = 0; // সিন/আনসিন নোটিফিকেশন সংখ্যা ট্র্যাক করার জন্য

  @override
  void initState() {
    super.initState();

    // রোল চেক করে যদি টিচার হয় তবে সরাসরি টিচারের হোমপেজে রিডাইরেক্ট করে দেওয়া[cite: 5]
    if (widget.role != 'super_admin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // আপনার তৈরি করা টিচারের হোমপেজ এখানে যুক্ত হবে[cite: 5]।
        Get.offAll(() => TeacherHomeView(userName: widget.userName));
      });
      return;
    }

    _loadStatsInitial();
    // ব্যাকগ্রাউন্ডে রিয়েল-টাইম বা পরিচালনা করার জন্য টাইমার[cite: 5]
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchAcademyStatsSilent();
      _fetchUnreadNoticeCount(); // রিয়েল-টাইমে নোটিফিকেশন সংখ্যা চেক করা[cite: 5]
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<bool> _checkInternet() async {
    // ফ্লাটার ওয়েব বা ব্রাউজারের ক্ষেত্রে ডার্ট আইও-এর ইন্টারনেট লুকআপ কাজ করে না,[cite: 5]
    // তাই ওয়েবের ক্ষেত্রে সরাসরি true রিটার্ন করা নিরাপদ[cite: 5]।
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

  // আনসিন নোটিফিকেশন সংখ্যা ফেচ করার ফাংশন[cite: 5]
  Future<void> _fetchUnreadNoticeCount() async {
    try {
      final academyId = await _getAcademyIdSafely();
      if (academyId == null) return;

      final currentUserEmail = supabase.auth.currentUser?.email;

      // নোটিশ টেবিল থেকে মোট নোটিশ অথবা ইউজারের স্ট্যাটাস চেক করে আনসিন সংখ্যা বের করা[cite: 5]
      final response = await supabase
          .from('notices')
          .select('id')
          .eq('academy_id', academyId);

      if (response != null && mounted) {
        // যদি আপনার ডাটাবেসে রিড/আনসিন ট্র্যাক করার আলাদা ফিল্ড বা লজিক থাকে তা এখানে কাজ করবে,[cite: 5]
        // আপাতত সামগ্রিক নোটিশ কাউন্ট বা আনসিন কাউন্ট দেখানো হলো[cite: 5]
        setState(() {
          _unreadNoticeCount = (response as List).length;
        });
      }
    } catch (e) {
      // সাইಲೆಂ্ট ক্যাচ[cite: 5]
    }
  }

  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  // নিরাপদভাবে বর্তমান ইউজারের ইমেইল দিয়ে একাডেমি ডেটা ও আইডি ফেচ করার ফাংশন[cite: 5]
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

      // শিক্ষক তালিকার জন্য query (বেতন এবং যোগদানের তারিখ সহ)[cite: 5]
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
      // student_other_collections টেবিল থেকে শিক্ষার্থীদের অন্যান্য ফি ফেচ করা[cite: 5]
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
                // চলতি বছর এবং চলতি মাস বা তার আগের মাসগুলোর ফিল্টার (ytdCollected এর সাথে মিল রেখে)[cite: 5]
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
        // সাইಲೆಂ্ট ক্যাচ[cite: 5]
      }

      // অন্যান্য আয় এবং শিক্ষার্থীদের অন্যান্য কালেকশন একসাথে যোগ করা[cite: 5]
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
            '৳ ${finalTotalOtherIncome.toStringAsFixed(0)}', // এখানে পরিবর্তন করা হয়েছে[cite: 5]
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

  // হেল্পার ফাংশন: ইমেইল দিয়ে সহজে academy_id বের করার জন্য[cite: 5]
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

  // ভুলবশত বা আগে ক্লিক করলে ইয়ার ভ্যালিডেশন চেক করার ফাংশন[cite: 5]
  void _checkAndShowYearTransitionDialog(BuildContext context) {
    int currentYear = DateTime.now().year; // বর্তমান বছর (যেমন: ২০২৬)[cite: 5]
    int targetExpectedYear = 2027; // যে বছর থেকে নতুন ক্লাস শুরু হবে[cite: 5]

    // যদি বর্তমান বছর টার্গেট বছরের চেয়ে কম হয়, তবে ওয়ার্নিং দিবে[cite: 5]
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
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            content: Text(
              _isEnglish
                  ? '2027 or new academic session has not started yet! (Current year: $currentYear).\n\nThis option is scheduled to be used only after the next year or new session begins.'
                  : 'এখনো ২০২৭ বা নতুন শিক্ষাবর্ষ শুরু হয়নি! (বর্তমান বছর: $currentYear)।\n\n'
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
                child: Text(_isEnglish ? 'Understood' : 'বুঝেছি'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } else {
      // বছর মিলে গেলে মূল কনফার্মেশন ডায়ালগ দেখাবে[cite: 5]
      _showYearTransitionConfirmationDialog(context);
    }
  }

  // কনফার্মেশন ডায়ালগ দেখানোর ফাংশন[cite: 5]
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
                  style: const TextStyle(
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
              child: Text(
                _isEnglish ? 'Cancel' : 'বাতিল',
                style: const TextStyle(color: Colors.grey),
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

  // ডাইনামিক ইয়ার ট্রানজিশন বা অটো-আপডেট এক্সিকিউট করার ফাংশন[cite: 5]
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

      // ডাটাবেস থেকে পাওয়া ক্লাসগুলোর ডাইনামিক তালিকা তৈরি[cite: 5]
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

      // ডাইনামিক নেক্সট ক্লাস ম্যাপ তৈরি[cite: 5]
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

        // পুরনো বছরের বকেয়া সংরক্ষণ টেবিলে সেভ করা[cite: 5]
        await supabase.from('yearly_due_history').insert({
          'academy_id': academyId,
          'student_id': studentId,
          'student_name': studentName,
          'class_name': className,
          'roll': roll,
          'due_amount': monthlyFee,
          'year': currentYear,
        });

        // পরবর্তী ক্লাসে আপডেট করা[cite: 5]
        String nextClass = dynamicClassSequence[className] ?? className;

        await supabase
            .from('students')
            .update({'class': nextClass})
            .eq('id', studentId);
      }

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

    // যদি সুপার অ্যাডমিন না হয়, তবে বিল্ড মেথডে লোডিং বা এম্পটি কন্টেইনার রিটার্ন করা যেতে পারে[cite: 5]
    // কারণ initState-েই রিডাইরেক্ট হ্যান্ডেল করা হয়েছে[cite: 5]।
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
        title: Text(
          isSuperAdmin
              ? (_isEnglish ? 'Admin Panel' : 'অ্যাডমিন প্যানেল')
              : (_isEnglish ? 'Teacher Dashboard' : 'শিক্ষক ড্যাশবোর্ড'),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ভাষা পরিবর্তনের বাটন (App Bar-এ যুক্ত করা হয়েছে)
          IconButton(
            icon: Text(
              _isEnglish ? 'BN' : 'EN',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            tooltip: _isEnglish ? 'বাংলা করুন' : 'Switch to English',
            onPressed: () {
              setState(() {
                _isEnglish = !_isEnglish;
              });
            },
          ),

          // অভিযোগ দেখার আইকন (এটি শুধুমাত্র সুপার অ্যাডমিন দেখতে পাবে)[cite: 5]
          if (isSuperAdmin)
            FutureBuilder<int>(
              future: () async {
                final academyId = await _getAcademyIdSafely();
                if (academyId == null) return 0;

                // পেন্ডিং অভিযোগগুলোর সংখ্যা বের করার কোড[cite: 5]
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
                      icon: const Icon(Icons.feedback, color: Colors.white),
                      tooltip: _isEnglish ? 'Complaints' : 'অভিযোগসমূহ',
                      onPressed: () async {
                        final academyId = await _getAcademyIdSafely();
                        if (academyId != null) {
                          // প্রতিষ্ঠান আইডি সহ পেজটি কল করা হচ্ছে[cite: 5]
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
                    // যদি পেন্ডিং অভিযোগ ১ বা তার বেশি থাকে, তবেই ব্যাজ দেখাবে[cite: 5]
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

          // অ্যাপবারের নোটিফিকেশন আইকন (সিন/আনসিন ব্যাজ সহ - শিক্ষক বা এডমিন উভয়ের জন্য)[cite: 5]
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
                    _fetchUnreadNoticeCount(); // নোটিশ ভিউ থেকে ফিরে আসলে কাউন্ট আপডেট হবে[cite: 5]
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
              title: Text(_isEnglish ? 'Home Dashboard' : 'হোম ড্যাশবোর্ড'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.campaign, color: Colors.teal),
              title: Text(_isEnglish ? 'Notice Board' : 'নোটিশ বোর্ড'),
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
              title: Text(_isEnglish ? 'Salary & Accounts' : 'বেতন ও হিসাব'),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            // সাইড ড্রয়ারে নতুন বছরের আপডেট অপশন[cite: 5]
            ListTile(
              leading: const Icon(Icons.update, color: Colors.teal),
              title: Text(
                _isEnglish ? 'Update to New Year' : 'নতুন বছরে আপডেট করুন',
              ),
              onTap: () {
                Navigator.pop(context);
                _checkAndShowYearTransitionDialog(context);
              },
            ),

            // ডিভাইডার এবং অন্যান্য প্রয়োজনীয় ফিচারসমূহ[cite: 5]
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.teal),
              title: Text(_isEnglish ? 'Settings' : 'সেটিংস'),
              onTap: () {
                Navigator.pop(context);
                // এখানে সেটিংস পেজে রাউট করতে পারেন[cite: 5]
              },
            ),
            ListTile(
              leading: const Icon(Icons.feedback, color: Colors.teal),
              title: Text(_isEnglish ? 'Feedback' : 'ফিডব্যাক'),
              onTap: () {
                Navigator.pop(context);
                // ফিডব্যাক লজিক যুক্ত করতে পারেন[cite: 5]
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.teal),
              title: Text(_isEnglish ? 'Privacy Policy' : 'প্রাইভেসি পলিসি'),
              onTap: () {
                Navigator.pop(context);
                // প্রাইভেসি পলিসি লিংক বা পেজ যুক্ত করতে পারেন[cite: 5]
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.teal),
              title: Text(_isEnglish ? 'Share App' : 'অ্যাপ শেয়ার'),
              onTap: () {
                Navigator.pop(context);
                // অ্যাপ শেয়ার লজিক যুক্ত করতে পারেন[cite: 5]
              },
            ),
            const Divider(),
            // একদম নিচে অ্যাপ ভার্সন[cite: 5]
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.grey),
              title: Text(
                _isEnglish ? 'App Version' : 'অ্যাপ ভার্সন',
                style: const TextStyle(color: Colors.grey),
              ),
              trailing: const Text(
                'v1.0.0',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                _isEnglish ? 'Logout' : 'লগআউট',
                style: const TextStyle(color: Colors.red),
              ),
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
            // ইন্টারনেট কানেকশন না থাকলে সতর্কবার্তা ব্যানার[cite: 5]
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
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.red, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isEnglish
                            ? 'You have no internet connection! Please check your internet connection.'
                            : 'আপনার ইন্টারনেট কানেকশন নেই! দয়া করে ইন্টারনেট সংযোগ চেক করুন।',
                        style: const TextStyle(
                          color: Colors.red,
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
              style: const TextStyle(
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
                      Row(
                        children: [
                          const Icon(
                            Icons.account_balance,
                            color: Colors.teal,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEnglish
                                ? 'Academy Overall Cash & Balance Calculation'
                                : 'একাডেমির সার্বিক ক্যাশ ও ব্যালেন্স হিসাব',
                            style: const TextStyle(
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
                            _isEnglish
                                ? 'Total Income (Collection + Other):'
                                : 'মোট আয় (বেতন উঠছে + অন্যান্য):',
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
                            _isEnglish
                                ? 'Total Expense (Teachers Salary + Other):'
                                : 'মোট ব্যয় (শিক্ষকদের বেতন + অন্যান্য):',
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
                          Text(
                            _isEnglish
                                ? 'Net Cash Balance:'
                                : 'নিট ক্যাশ ব্যালেন্স:',
                            style: const TextStyle(
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                _buildDashboardCard(
                  icon: Icons.people_alt_rounded,
                  title: _isEnglish ? 'Students List' : 'ছাত্র-ছাত্রী তালিকা',
                  color: Colors.teal.shade50,
                  iconColor: Colors.teal.shade800,
                  onTap: () async {
                    await Get.to(() => StudentsView(userRole: widget.role));
                    _loadStatsInitial();
                  },
                ),
                _buildDashboardCard(
                  icon: Icons.payment_rounded,
                  title: _isEnglish ? 'Fee Collection' : 'বেতন ও ফি সংগ্রহ',
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
                  color: Colors.brown.shade50,
                  iconColor: Colors.brown.shade800,
                  onTap: () async {
                    final fetchedAcademyId = await _getAcademyIdSafely();
                    if (fetchedAcademyId != null) {
                      await Get.to(
                        () => ModelTestView(academyId: fetchedAcademyId),
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
                  icon: Icons.note_alt_rounded,
                  title: _isEnglish ? 'Exam Result' : 'পরীক্ষার রেজাল্ট',
                  color: Colors.purple.shade50,
                  iconColor: Colors.purple.shade800,
                  onTap: () {
                    Get.to(
                      () => AcademyResultManagementView(
                        academyId: widget
                            .academyId, // আপনার উইজেটে থাকা academyId এখানে পাস করা হলো
                        currentUserId: widget.currentUserId,
                        currentUserName: widget.currentUserName,
                      ),
                    );
                  },
                ),
                if (isSuperAdmin)
                  _buildDashboardCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: _isEnglish ? 'Add Teacher' : 'নতুন শিক্ষক যোগ',
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
                    title: _isEnglish
                        ? 'Income / Expense'
                        : 'অন্যান্য আয় ব্যয়',
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
                    color: Colors.deepPurple.shade50,
                    iconColor: Colors.deepPurple.shade800,
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
                    icon: Icons.quiz_rounded,
                    title: _isEnglish ? 'Syllabus Create' : 'সিলেবাস তৈরি',
                    color: Colors.deepPurple.shade50,
                    iconColor: Colors.teal.shade800,
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
            border: Border.all(color: iconColor.withOpacity(0.15)),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: iconColor.withOpacity(0.9),
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
