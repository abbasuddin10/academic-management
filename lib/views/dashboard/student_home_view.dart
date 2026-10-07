import 'package:academy_management/views/auth/login_view.dart';
import 'package:academy_management/views/dashboard/student_attendance_view.dart';
import 'package:academy_management/views/dashboard/student_complaint_view.dart';
import 'package:academy_management/views/dashboard/student_exam_routine_view.dart';
import 'package:academy_management/views/dashboard/student_fee_details_view.dart';
import 'package:academy_management/views/dashboard/student_model_test.dart';
import 'package:academy_management/views/dashboard/student_teachers_view.dart';
// আপনার তৈরি করা রুটিন পেজটি ইমপোর্ট করুন (ফাইল পাথ ঠিক না থাকলে আপনার প্রজেক্ট অনুযায়ী অ্যাডজাস্ট করে নেবেন)
import 'package:academy_management/views/dashboard/student_routine_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentHomeView extends StatefulWidget {
  final String studentName;
  final String academyName;
  final String className;
  final String roll;

  const StudentHomeView({
    super.key,
    required this.studentName,
    required this.academyName,
    required this.className,
    required this.roll,
  });

  @override
  State<StudentHomeView> createState() => _StudentHomeViewState();
}

class _StudentHomeViewState extends State<StudentHomeView> {
  bool isLoading = true;
  bool hasError = false; // ইন্টারনেট বা নেটওয়ার্ক ত্রুটির জন্য
  Map<String, dynamic>? studentDetails;
  List<Map<String, dynamic>> noticesList = [];
  List<Map<String, dynamic>> feeHistoryList = [];

  // আজকের উপস্থিতির স্ট্যাটাস রাখার জন্য ভেরিয়েবল
  String _todayAttendanceStatus = 'তথ্য নেই';

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  // ডাটাবেস থেকে স্টুডেন্টের সঠিক তথ্য, ফি-এর হিস্ট্রি, নোটিশ এবং আজকের উপস্থিতি ফেচ করা
  Future<void> fetchAllData() async {
    try {
      setState(() {
        hasError = false;
      });

      final supabase = Supabase.instance.client;

      // ১. ডাটাবেস থেকে নাম এবং রোল দিয়ে স্টুডেন্টের ইউনিক আইডি (id) সহ অন্যান্য ডেটা আনা
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

        // ২. নির্দিষ্ট স্টুডেন্টের ফি কালেকশন হিস্ট্রি আনা
        final feeResponse = await supabase
            .from('student_fee_history')
            .select()
            .eq('student_id', studentId);

        feeHistoryList = List<Map<String, dynamic>>.from(feeResponse);

        // ৩. student_attendance টেবিল থেকে student_id এবং আজকের তারিখ দিয়ে উপস্থিতি চেক করা
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

      // ৪. নোটিশ ফেচ করা এবং ক্লাস অনুযায়ী ফিল্টার করা
      final academyId = studentResponse?['academy_id'] ?? '';
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
    } catch (e) {
      print("Error fetching data: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true; // নেট বা সার্ভার প্রবলেম হলে এরর ট্রু হবে
      });
    }
  }

  // সব নোটিশ একসাথে পপআপ বা ফুল পেজে দেখানোর ফাংশন
  void _showAllNoticesDialog() {
    Get.to(
      () => Scaffold(
        appBar: AppBar(
          title: const Text('সকল নোটিশ'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        body: noticesList.isEmpty
            ? const Center(
                child: Text(
                  'এই মুহূর্তে কোনো নোটিশ নেই।',
                  style: TextStyle(color: Colors.grey),
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
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.campaign,
                                color: Colors.indigo,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notice['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notice['description'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const Divider(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              notice['created_at'] != null
                                  ? notice['created_at'].toString().substring(
                                      0,
                                      10,
                                    )
                                  : '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // নতুন পেজে নেভিগেট করার ফাংশন (বেতনের তথ্য)
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        Get.offAll(() => const LoginView());
      }
    } catch (e) {
      print("Logout Error: $e");
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
        Future.delayed(const Duration(milliseconds: 150), () {
          _logoutStudent();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isPresent = _todayAttendanceStatus == 'উপস্থিত';

    // সুপাবেস থেকে পাওয়া প্রফাইল ছবির লিংক (image_url)
    String? profileImageUrl = studentDetails?['image_url'];

    return Scaffold(
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton.extended(
          onPressed: () {
            Get.snackbar(
              'একাডেমি অ্যাসিস্ট্যান্ট',
              'খুব শীঘ্রই এআই চ্যাটবট ফিচারটি চালু হচ্ছে!',
              backgroundColor: Colors.indigo.shade50,
              colorText: Colors.indigo.shade900,
              snackPosition: SnackPosition.BOTTOM,
              margin: const EdgeInsets.all(16),
              borderRadius: 12,
              icon: const Icon(
                Icons.support_agent_rounded,
                color: Colors.indigo,
              ),
            );
          },
          backgroundColor: Colors.indigo,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          icon: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          label: const Row(
            children: [
              Text(
                'AI assistant',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'শিক্ষার্থী ড্যাশবোর্ড',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () {
              _showAllNoticesDialog();
            },
          ),
        ],
      ),

      // --- সুন্দর ও আপডেট করা নেভিগেশন ড্রয়ার ---
      drawer: Drawer(
        child: Column(
          children: [
            // কাস্টম হেডার সেকশন (প্রোফাইল ও প্রতিষ্ঠানের নাম মাঝবরাবর করা হয়েছে)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 48,
                bottom: 20,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
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
                    backgroundColor: Colors.white,
                    backgroundImage:
                        (profileImageUrl != null && profileImageUrl.isNotEmpty)
                        ? NetworkImage(profileImageUrl)
                        : null,
                    child: (profileImageUrl == null || profileImageUrl.isEmpty)
                        ? Text(
                            widget.studentName.isNotEmpty
                                ? widget.studentName[0]
                                : 'S',
                            style: const TextStyle(
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.academyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ড্রয়ারের মূল মেনু ও এক্সট্রা অপশনসমূহ
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  // --- মেইন একাডেমিক ফিচারস ---
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
                    onTap: () async {
                      Navigator.pop(context);
                      final Uri privacyUrl = Uri.parse(
                        'https://your-privacy-policy-url.com',
                      );
                      if (await canLaunchUrl(privacyUrl)) {
                        await launchUrl(
                          privacyUrl,
                          mode: LaunchMode.externalApplication,
                        );
                      }
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
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: const Text(
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
      body: Stack(
        children: [
          hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          size: 60,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ইন্টারনেট কানেকশন নেই অথবা ডাটা লোড করতে সমস্যা হচ্ছে।',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ১. প্রোফাইল কার্ড
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withOpacity(0.12),
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
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.indigo.shade50,
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
                                          style: const TextStyle(
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
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
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
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.academyName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'শ্রেণি: ${widget.className}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.indigo,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'রোল: ${widget.roll}',
                                              style: const TextStyle(
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
                        const SizedBox(height: 25),

                        // ২. ফিচার কার্ডসমূহ
                        const Text(
                          'একাডেমিক কার্যক্রম',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ১ম সারি: মডেল টেস্ট, উপস্থিতি, বেতন
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
                                  Get.to(
                                    () => StudentModelTestView(
                                      academyId: academyId,
                                      className: widget.className,
                                      studentId: studentId,
                                    ),
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
                                  Get.to(
                                    () => StudentAttendanceView(
                                      studentId: studentId,
                                      studentName: widget.studentName,
                                    ),
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
                                onTap: _navigateToFeeDetailsPage,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ২য় সারি: শিক্ষকগণ, সিলেবাস, ক্লাশ রুটীন
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
                                  Get.to(
                                    () => StudentTeachersView(
                                      academyId: academyId,
                                      academyName: widget.academyName,
                                    ),
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
                                onTap: () async {
                                  String academyId =
                                      studentDetails?['academy_id'] ?? '';
                                  String className = widget.className.trim();

                                  if (academyId.isEmpty || className.isEmpty) {
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
                                        .order('created_at', ascending: false)
                                        .limit(1);

                                    if (response != null &&
                                        (response as List).isNotEmpty) {
                                      String fileUrl =
                                          response[0]['file_url'] ?? '';

                                      if (fileUrl.isNotEmpty) {
                                        final Uri uri = Uri.parse(fileUrl);

                                        if (await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
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
                                  Get.to(
                                    () => StudentRoutineView(
                                      academyId: academyId,
                                      className: widget.className,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ৩য় সারি: অভিযোগ, রেজাল্ট, পরিক্ষা রু.
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
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFeatureCard(
                                title: 'রেজাল্ট দেখুন',
                                icon: Icons.insert_chart_rounded,
                                color: Colors.orange,
                                onTap: () {},
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
                                  Get.to(
                                    () => StudentExamRoutineView(
                                      academyId: academyId,
                                      className: widget.className,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 25),

                        // ৩. সর্বশেষ নোটিশসমূহ সেকশন
                        const Text(
                          'সর্বশেষ নোটিশসমূহ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        noticesList.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'এই মুহূর্তে কোনো নতুন নোটিশ নেই',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: noticesList.length > 5
                                    ? 5
                                    : noticesList.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final notice = noticesList[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.campaign_rounded,
                                            size: 20,
                                            color: Colors.blue,
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
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                notice['description'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
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
    );
  }

  Widget _buildAnimatedDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.indigo.shade300),
        const SizedBox(width: 10),
        Text(
          '$title: ',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 115,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
