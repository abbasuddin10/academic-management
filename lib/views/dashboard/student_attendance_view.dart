import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAttendanceView extends StatefulWidget {
  final String studentId;
  final String studentName;

  const StudentAttendanceView({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentAttendanceView> createState() => _StudentAttendanceView();
}

class _StudentAttendanceView extends State<StudentAttendanceView> {
  bool isFetching = true;
  List<Map<String, dynamic>> attendanceList = [];
  int totalClasses = 0;
  int totalPresent = 0;
  int totalAbsent = 0;
  Map<String, int> monthlyPresentMap = {};

  @override
  void initState() {
    super.initState();
    fetchAttendanceHistory();
  }

  // ব্যাকগ্রাউন্ডে ডাটা ফেচ করার ফাংশন
  Future<void> fetchAttendanceHistory() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('student_attendance')
          .select()
          .eq('student_id', widget.studentId)
          .order('date', ascending: false);

      List<Map<String, dynamic>> fetchedData = List<Map<String, dynamic>>.from(
        response,
      );

      int presentCount = 0;
      int absentCount = 0;
      Map<String, int> tempMonthlyMap = {};

      for (var item in fetchedData) {
        String status = item['status']?.toString() ?? '';
        String dateStr = item['date']?.toString() ?? '';

        if (status == 'Present') {
          presentCount++;

          if (dateStr.isNotEmpty) {
            try {
              DateTime parsedDate = DateTime.parse(dateStr);
              // মাস এবং বছর অনুযায়ী ডাইনামিক কি (যেমন: Sep 2026)
              String monthKey = DateFormat('MMM yyyy').format(parsedDate);
              tempMonthlyMap[monthKey] = (tempMonthlyMap[monthKey] ?? 0) + 1;
            } catch (_) {}
          }
        } else if (status == 'Absent') {
          absentCount++;
        }
      }

      if (!mounted) return;

      setState(() {
        attendanceList = fetchedData;
        totalClasses = fetchedData.length;
        totalPresent = presentCount;
        totalAbsent = absentCount;
        monthlyPresentMap = tempMonthlyMap;
        isFetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isFetching = false;
      });
    }
  }

  // বারের নাম বাংলায় কনভার্ট করার ফাংশন
  String getBanglaDayName(String dateStr) {
    try {
      DateTime parsedDate = DateTime.parse(dateStr);
      String engDay = DateFormat('EEEE').format(parsedDate);
      return switch (engDay) {
        'Monday' => 'সোমবার',
        'Tuesday' => 'মঙ্গলবার',
        'Wednesday' => 'বুধবার',
        'Thursday' => 'বৃহস্পতিবার',
        'Friday' => 'শুক্রবার',
        'Saturday' => 'শনিবার',
        'Sunday' => 'রবিবার',
        _ => engDay,
      };
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> last6DaysList = attendanceList.take(6).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'উপস্থিতির হিস্ট্রি',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ব্যাকগ্রাউন্ডে ডাটা লোড হওয়ার সময় ছোট একটি ইন্ডিকেটর দেখাবে, পেজ আটকাবে না
          if (isFetching)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchAttendanceHistory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ১. মোট উপস্থিতি কার্ড (ডিজাইন সবসময় শো করবে)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.indigo, Colors.indigoAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildHeaderStatItem(
                      title: 'মোট ক্লাস',
                      value: '$totalClasses দিন',
                      icon: Icons.class_rounded,
                    ),
                    Container(height: 40, width: 1, color: Colors.white38),
                    _buildHeaderStatItem(
                      title: 'উপস্থিত',
                      value: '$totalPresent দিন',
                      icon: Icons.check_circle_rounded,
                    ),
                    Container(height: 40, width: 1, color: Colors.white38),
                    _buildHeaderStatItem(
                      title: 'অনুপস্থিত',
                      value: '$totalAbsent দিন',
                      icon: Icons.cancel_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              // ২. সর্বশেষ ৬ দিনের রেকর্ড সেকশন
              const Text(
                'সর্বশেষ ৬ দিনের উপস্থিতি রেকর্ড',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              attendanceList.isEmpty && isFetching
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30.0),
                        child: CircularProgressIndicator(color: Colors.indigo),
                      ),
                    )
                  : last6DaysList.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'কোনো উপস্থিতি রেকর্ড পাওয়া যায়নি',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: last6DaysList.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final record = last6DaysList[index];
                        String dateStr = record['date'] ?? '';
                        String status = record['status'] ?? '';
                        bool isPresent = status == 'Present';

                        String formattedDate = dateStr;
                        String dayName = '';
                        try {
                          DateTime parsedDate = DateTime.parse(dateStr);
                          formattedDate = DateFormat(
                            'dd MMM yyyy',
                          ).format(parsedDate);
                          dayName = getBanglaDayName(dateStr);
                        } catch (_) {}

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isPresent
                                          ? Colors.green.shade50
                                          : Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPresent ? Icons.check : Icons.close,
                                      color: isPresent
                                          ? Colors.green
                                          : Colors.red,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formattedDate,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isPresent ? 'উপস্থিত' : 'অনুপস্থিত',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isPresent
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 25),

              // ৩. মাস ভিত্তিক সামারি সেকশন (এক লাইনে ৩টি করে স্মার্ট কার্ড)
              const Text(
                'মাসভিত্তিক উপস্থিতি সামারি',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              monthlyPresentMap.isEmpty
                  ? const SizedBox()
                  : GridView.builder(
                      itemCount: monthlyPresentMap.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                      itemBuilder: (context, index) {
                        String monthKey = monthlyPresentMap.keys.elementAt(
                          index,
                        );
                        int presentDays = monthlyPresentMap[monthKey]!;

                        return Container(
                          padding: const EdgeInsets.all(10),
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
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                monthKey,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$presentDays দিন',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'উপস্থিত',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildHeaderStatItem({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
