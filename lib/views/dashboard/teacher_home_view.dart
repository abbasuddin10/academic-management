import 'dart:async';
import 'package:academy_management/views/dashboard/Model_Test_View.dart';
import 'package:academy_management/views/dashboard/TeacherRoutineView.dart';
import 'package:academy_management/views/dashboard/question_create_view.dart';
import 'package:academy_management/views/dashboard/student_attendance_page_view.dart';
import 'package:academy_management/views/dashboard/teacher_exam_routine_view.dart';
import 'package:academy_management/views/dashboard/teacher_profile.dart';
import 'package:academy_management/views/dashboard/teacher_salary_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../auth/login_view.dart';
import '../student/students_view.dart';
import 'attendance_page_view.dart';
import 'notice_board_view.dart';

class TeacherHomeView extends StatefulWidget {
  final String userName;

  const TeacherHomeView({Key? key, required this.userName}) : super(key: key);

  @override
  State<TeacherHomeView> createState() => _TeacherHomeViewState();
}

class _TeacherHomeViewState extends State<TeacherHomeView> {
  final supabase = Supabase.instance.client;

  String teacherId = '';
  String teacherName = '';
  String teacherEmail = '';
  String academyId = '';
  String photoUrl = '';
  double monthlySalary = 0.0;
  double paidSalary = 0.0;
  double dueSalary = 0.0;
  bool isAttendanceGivenToday = false;
  bool hasInternet = true;

  List<Map<String, dynamic>> routines = [];
  Timer? _timer;
  DateTime _now = DateTime.now();

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

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
              .eq('email', teacherEmail)
              .gte('created_at', '$today 00:00:00');

          if (attendanceResponse != null &&
              (attendanceResponse as List).isNotEmpty) {
            tempAttendance = true;
          }
        } catch (e) {
          print("Attendance fetch error: $e");
        }

        try {
          final salaryHistory = await supabase
              .from('teacher_salary_history')
              .select('amount')
              .eq('academy_id', tempAcademyId)
              .eq('teacher_id', tempId);

          if (salaryHistory != null) {
            for (var item in (salaryHistory as List)) {
              tempPaid +=
                  double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
            }
          }
        } catch (e) {
          print("Salary history fetch error: $e");
        }

        tempDue = tempSalary - tempPaid;
        if (tempDue < 0) tempDue = 0;

        try {
          final routineRes = await supabase
              .from('class_routines')
              .select()
              .eq('academy_id', tempAcademyId)
              .eq('teacher_id', tempId);

          if (routineRes != null) {
            tempRoutines = List<Map<String, dynamic>>.from(routineRes);
          }
        } catch (e) {
          print("Routine fetch error: $e");
        }

        try {
          final noticeRes = await supabase
              .from('notices')
              .select('title, description, created_at')
              .eq('academy_id', tempAcademyId)
              .order('created_at', ascending: false)
              .limit(3);

          if (noticeRes != null) {
            tempNotices = List<Map<String, dynamic>>.from(noticeRes);
          }
        } catch (e) {}
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
    } catch (e) {
      print("Error fetching teacher data: $e");
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    try {
      await supabase.auth.signOut();
    } catch (e) {}

    Get.offAll(() => const LoginView());
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
        remainingTimeText = 'শেষ হতে বাকি: ${remMins}মি ${remSecs}সে';
      } else {
        remainingTimeText = 'ক্লাস শেষের পথে';
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.teal,
        title: const Text(
          'শিক্ষক প্যানেল',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              },
              child: Stack(
                children: [
                  // প্রফাইল ছবি বা ডিফল্ট আইকন
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child:
                          (photoUrl.isNotEmpty && photoUrl.startsWith('http'))
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.fill,
                              width: 36,
                              height: 36,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.teal,
                                );
                              },
                            )
                          : const Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.teal,
                            ),
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

          // নোটিফিকেশন আইকন
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () {
                    if (academyId.isNotEmpty) {
                      Get.to(
                        () => NoticeBoardView(
                          academyId: academyId,
                          userRole: 'teacher',
                        ),
                      );
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
                // ডানে ও উপরে লাল ব্যাজ (এখানে চাইলে সংখ্যা বা শুধু লাল ডট রাখা যাবে)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    // padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red, // লাল রঙ
                      shape: BoxShape.circle,
                      //border: Border.all(color: Colors.teal),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 10,
                      minHeight: 10,
                    ),
                    // যদি সংখ্যা দেখাতে চান যেমন '3', তবে এখানে Text উইজেট দিতে পারেন।
                    // শুধু ডট রাখতে চাইলে child: null বা ফাঁকা রাখতে পারেন।
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      drawer: Drawer(
        child: Column(
          children: [
            // কাস্টম হেডার সেকশন (অ্যাপবারের সাথে মিল রেখে সলিড টিল কালার এবং তথ্য মাঝবরাবর করা হয়েছে)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 48,
                bottom: 20,
                left: 16,
                right: 16,
              ),
              color:
                  Colors.teal, // অ্যাপবারের কালারের সাথে হুবহু মিল রাখা হয়েছে
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child:
                          (photoUrl.isNotEmpty && photoUrl.startsWith('http'))
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.fill,
                              width: 64,
                              height: 64,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.person,
                                  size: 32,
                                  color: Colors.teal,
                                );
                              },
                            )
                          : const Icon(
                              Icons.person,
                              size: 32,
                              color: Colors.teal,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    teacherName.isNotEmpty ? teacherName : 'শিক্ষক',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teacherEmail.isNotEmpty ? teacherEmail : '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    leading: const Icon(Icons.home, color: Colors.teal),
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
                    leading: const Icon(Icons.groups, color: Colors.blue),
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
                    leading: const Icon(Icons.fact_check, color: Colors.green),
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
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.notifications_active,
                      color: Colors.orange,
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
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(thickness: 1, color: Colors.grey),
                  ),

                  // --- এক্সট্রা সেটিংস ও পলিসি সেকশন ---
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
                      Get.snackbar("সেটিংস", "সেটিংস ফিচারটি খুব শীঘ্রই আসছে!");
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
                      Get.snackbar("ফিডব্যাক", "আপনার মতামতের জন্য ধন্যবাদ!");
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.privacy_tip_outlined,
                      color: Colors.brown,
                    ),
                    title: const Text(
                      'প্রাইভেসি পলিসি',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.snackbar(
                        "প্রাইভেসি পলিসি",
                        "পলিসি লিংক ব্রাউজারে ওপেন হবে",
                      );
                    },
                  ),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.share_outlined,
                      color: Colors.teal,
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
                      Get.snackbar(
                        "শেয়ার",
                        "প্লে-স্টোর লিংক কপি বা শেয়ার অপশন",
                      );
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // লগআউট অপশন
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: Colors.red.shade50,
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'লগআউট',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onTap: _logout,
              ),
            ),

            // একদম নিচে অ্যাপের ভার্সন প্রদর্শন
            const Padding(
              padding: EdgeInsets.only(bottom: 16.0, top: 4.0),
              child: Text(
                'App Version: 1.0.0',
                style: TextStyle(
                  color: Colors.grey,
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
              color: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'ইন্টারনেট সংযোগ নেই! দয়া করে ইন্টারনেট কানেক্ট করুন।',
                    style: TextStyle(
                      color: Colors.white,
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00796B), Color(0xFF004D40)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
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
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      children: [
                        _buildMenuCard(
                          title: 'ছাত্রছাত্রী তালিকা',
                          icon: Icons.groups,
                          color: Colors.blue.shade50,
                          iconColor: Colors.blue.shade700,
                          onTap: () => Get.to(
                            () => const StudentsView(userRole: 'teacher'),
                          ),
                        ),
                        _buildMenuCard(
                          title: 'ছাত্রছাত্রীদের হাজিরা',
                          icon: Icons.fact_check,
                          color: Colors.green.shade50,
                          iconColor: Colors.green.shade700,
                          onTap: () {
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
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
                          },
                        ),
                        _buildMenuCard(
                          title: 'আমার হাজিরা',
                          icon: Icons.how_to_reg,
                          color: Colors.teal.shade50,
                          iconColor: Colors.teal.shade700,
                          onTap: () {
                            if (academyId.isNotEmpty) {
                              Get.to(
                                () => AttendancePageView(
                                  academyId: academyId,
                                  userRole: 'teacher',
                                ),
                              );
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
                        _buildMenuCard(
                          title: 'ক্লাস রুটিন',
                          icon: Icons.schedule,
                          color: Colors.purple.shade50,
                          iconColor: Colors.purple.shade700,
                          onTap: () {
                            if (academyId.isNotEmpty && teacherId.isNotEmpty) {
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
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
                          },
                        ),

                        _buildMenuCard(
                          title: 'পরীক্ষার ফলাফল',
                          icon: Icons.assessment,
                          color: Colors.indigo.shade50,
                          iconColor: Colors.indigo.shade700,
                          onTap: () {
                            Get.snackbar(
                              "তথ্য",
                              "ফলাফল সেকশনটি শীঘ্রই আসছে",
                              backgroundColor: Colors.indigo,
                              colorText: Colors.white,
                            );
                          },
                        ),
                        _buildMenuCard(
                          title: 'এক্সাম রুটিন',
                          icon: Icons.event_note,
                          color: Colors.cyan.shade50,
                          iconColor: Colors.cyan.shade700,
                          onTap: () {
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
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
                          },
                        ),

                        _buildMenuCard(
                          title: 'বেতন ও বকেয়া',
                          icon: Icons.account_balance_wallet,
                          color: const Color.fromARGB(255, 236, 238, 249),
                          iconColor: const Color.fromARGB(255, 7, 120, 165),
                          onTap: () {
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
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
                          },
                        ),
                        _buildMenuCard(
                          title: 'পরীক্ষা তৈরি',
                          icon: Icons.assignment_add,
                          color: Colors.teal.shade50,
                          iconColor: Colors.teal.shade700,
                          onTap: () {
                            // 👈 এখানে একাডেমি আইডি এবং শিক্ষকের আইডি উভয়ই চেক করা হচ্ছে
                            if (academyId.isNotEmpty && teacherId.isNotEmpty) {
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
                                backgroundColor: Colors.orange,
                                colorText: Colors.white,
                              );
                            }
                          },
                        ),
                        _buildMenuCard(
                          icon: Icons.quiz_rounded,
                          title: 'প্রশ্ন তৈরি',
                          color: Colors.deepPurple.shade50,
                          iconColor: Colors.deepPurple.shade800,
                          onTap: () {
                            // সরাসরি ক্লাসের নিজস্ব academyId এবং teacherId (বা supabase id) ব্যবহার করা হলো
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
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
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
                        ? const Card(
                            elevation: 0,
                            color: Colors.white,
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text('কোনো নোটিশ পাওয়া যায়নি'),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: latestNotices.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final notice = latestNotices[index];
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.teal,
                                    child: Icon(
                                      Icons.notifications,
                                      color: Colors.white,
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
          border: Border.all(color: iconColor.withOpacity(0.2)),
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
