import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class StudentModelTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String studentId;

  const StudentModelTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.studentId,
  });

  @override
  State<StudentModelTestView> createState() => _StudentModelTestViewState();
}

class _StudentModelTestViewState extends State<StudentModelTestView> {
  bool isLoading = true;
  List<Map<String, dynamic>> modelTestList = [];
  bool isReminderSet = false; // রিমাইন্ডার সেট আছে কিনা তা ট্র্যাক করার জন্য

  @override
  void initState() {
    super.initState();
    fetchModelTests();
  }

  Future<void> fetchModelTests() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('exam_schedules')
          .select()
          .eq('academy_id', widget.academyId)
          .ilike('class_name', widget.className.trim())
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          List<Map<String, dynamic>> fetchedList =
              List<Map<String, dynamic>>.from(response);

          DateTime now = DateTime.now();

          for (var test in fetchedList) {
            String? endTimeStr = test['end_time'];

            if (endTimeStr != null && endTimeStr.isNotEmpty) {
              try {
                DateTime endDt = DateTime.parse(endTimeStr);
                if (endDt.isBefore(now)) {
                  test['is_active'] = false;
                }
              } catch (e) {
                // ইগনোর
              }
            }
          }

          // সাজানো: প্রথমে রানিং (active) এবং পরে ইনঅ্যাক্টিভ (inactive)
          fetchedList.sort((a, b) {
            bool aActive = a['is_active'] ?? false;
            bool bActive = b['is_active'] ?? false;
            if (aActive == bActive) return 0;
            return aActive ? -1 : 1;
          });

          modelTestList = fetchedList;
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching model tests: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // রিমাইন্ডার সেট বা বাতিল করার ডায়ালগ লজিক
  void _showReminderDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isReminderSet ? 'রিমাইন্ডার বাতিল করুন' : 'রিমাইন্ডার সেট করুন',
        ),
        content: Text(
          isReminderSet
              ? 'আপনি কি রানিং পরীক্ষাগুলোর জন্য সেট করা রিমাইন্ডারটি বন্ধ করতে চান?'
              : 'আপনি কি রানিং পরীক্ষাগুলোর জন্য ৫ মিনিট পূর্বে রিমাইন্ডার পেতে চান?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ফিরে যান', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isReminderSet ? Colors.red : Colors.indigo,
            ),
            onPressed: () {
              Navigator.pop(context);
              if (isReminderSet) {
                _cancelReminders();
              } else {
                _setRemindersForActiveExams();
              }
            },
            child: Text(
              isReminderSet ? 'হ্যাঁ, বন্ধ করুন' : 'হ্যাঁ, সেট করুন',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // রিমাইন্ডার সেট করার মূল ফাংশন
  void _setRemindersForActiveExams() {
    List<Map<String, dynamic>> activeList = modelTestList
        .where((test) => test['is_active'] == true)
        .toList();

    if (activeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('এই মুহূর্তে কোনো রানিং পরীক্ষা নেই!')),
      );
      return;
    }

    setState(() {
      isReminderSet = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'সকল রানিং পরীক্ষার জন্য ৫ মিনিট পূর্বে রিমাইন্ডার সেট করা হয়েছে!',
        ),
        backgroundColor: Colors.teal,
      ),
    );
  }

  // রিমাইন্ডার বাতিল করার ফাংশন
  void _cancelReminders() {
    setState(() {
      isReminderSet = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('পরীক্ষার রিমাইন্ডার সফলভাবে বাতিল করা হয়েছে।'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  String formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return '';
    try {
      DateTime dt = DateTime.parse(dateTimeStr);
      DateTime parsedDate = DateTime(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
      );

      String formattedTime = DateFormat('hh:mm a').format(parsedDate);
      String formattedDate = DateFormat('dd MMM, yyyy').format(parsedDate);

      int hour = parsedDate.hour;
      String timePeriod = '';
      if (hour >= 4 && hour < 12) {
        timePeriod = 'সকাল';
      } else if (hour >= 12 && hour < 15) {
        timePeriod = 'দুপুর';
      } else if (hour >= 15 && hour < 18) {
        timePeriod = 'বিকাল';
      } else if (hour >= 18 && hour < 21) {
        timePeriod = 'সন্ধ্যা';
      } else {
        timePeriod = 'রাত';
      }

      return '$formattedDate, $timePeriod $formattedTime';
    } catch (e) {
      return dateTimeStr;
    }
  }

  // রেজাল্ট ডায়ালগ
  void _showResultDialog(Map<String, dynamic> test) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(test['exam_title'] ?? 'পরীক্ষার ফলাফল'),
        content: const Text(
          'এই পরীক্ষার ফলাফল বা আপনার প্রাপ্ত নম্বর এখানে দেখতে পাবেন।',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বন্ধ করুন'),
          ),
        ],
      ),
    );
  }

  // ২য় সুযোগ ডায়ালগ
  void _showRetestDialog(Map<String, dynamic> test) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('২য় সুযোগ (Re-test)'),
        content: const Text(
          'আপনি কি এই পরীক্ষায় আবার অংশগ্রহণ করতে চান?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () {
              Navigator.pop(context);
              // ২য় সুযোগে পরীক্ষা শুরুর লজিক
            },
            child: const Text(
              'শুরু করুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> activeList = modelTestList
        .where((test) => test['is_active'] == true)
        .toList();
    List<Map<String, dynamic>> inactiveList = modelTestList
        .where((test) => test['is_active'] == false)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('মডেল টেস্ট ও পরীক্ষা'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _showReminderDialog,
            style: TextButton.styleFrom(
              foregroundColor: isReminderSet
                  ? Colors.amberAccent
                  : Colors.white,
            ),
            icon: Icon(
              isReminderSet
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
            ),
            label: Text(
              isReminderSet ? 'রিমাইন্ডার অন' : 'রিমাইন্ডার',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressGraphSection(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'রানিং পরীক্ষা (Active Exams)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.indigo,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            isLoading && modelTestList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'পরীক্ষার তথ্য লোড হচ্ছে...',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  )
                : activeList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'এই মুহূর্তে কোনো রানিং পরীক্ষা নেই।',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    children: activeList
                        .map((test) => _buildExamCard(test, true))
                        .toList(),
                  ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'পূর্ববর্তী পরীক্ষা ও ফলাফল (Inactive Exams)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            isLoading && modelTestList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'পূর্ববর্তী রেকর্ড লোড হচ্ছে...',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  )
                : inactiveList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'কোনো পূর্ববর্তী পরীক্ষার রেকর্ড নেই।',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    children: inactiveList
                        .map((test) => _buildExamCard(test, false))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressGraphSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'আপনার পরীক্ষার অগ্রগতি (Progress)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              Icon(Icons.insights, color: Colors.indigo, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBarItem('জানু', 0.6),
              _buildBarItem('ফেব্রু', 0.4),
              _buildBarItem('মার্চ', 0.8),
              _buildBarItem('এপ্রিল', 0.5),
              _buildBarItem('মে', 0.9),
              _buildBarItem('জুন', 0.7),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarItem(String month, double heightFactor) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 80 * heightFactor,
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          month,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildExamCard(Map<String, dynamic> test, bool isActive) {
    String startTime = test['start_time']?.toString() ?? '';
    String endTime = test['end_time']?.toString() ?? '';
    String formattedStartTime = formatDateTime(startTime);
    String formattedEndTime = formatDateTime(endTime);

    // পরীক্ষার মোট সময়কাল (Duration) হিসাব করা
    String durationText = '';
    if (startTime.isNotEmpty && endTime.isNotEmpty) {
      try {
        DateTime startDt = DateTime.parse(startTime);
        DateTime endDt = DateTime.parse(endTime);
        Duration diff = endDt.difference(startDt);
        int hours = diff.inHours;
        int minutes = diff.inMinutes % 60;
        if (hours > 0 && minutes > 0) {
          durationText = '$hours ঘণ্টা $minutes মিনিট';
        } else if (hours > 0) {
          durationText = '$hours ঘণ্টা';
        } else {
          durationText = '$minutes মিনিট';
        }
      } catch (e) {
        durationText = '';
      }
    }

    // অধ্যায়ের নাম চেক করা (না থাকলে "সম্পুর্ন বই" দেখাবে)
    String? chapterName = test['chapter_name'];
    String displayChapter =
        (chapterName != null && chapterName.toString().trim().isNotEmpty)
        ? chapterName.toString()
        : 'সম্পুর্ন বই';

    // প্রশ্ন সংখ্যা ও তৈরি করা স্যারের নাম
    String questionCount = test['question_count']?.toString() ?? '০';
    String creatorName =
        test['question_creator_name']?.toString() ?? 'নির্ধারিত নেই';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.quiz_rounded,
                  color: isActive ? Colors.black : Colors.grey,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    test['exam_title'] ?? 'পরীক্ষার নাম নেই',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isActive ? Colors.black87 : Colors.grey.shade700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: isActive ? Colors.teal : Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // স্যারের নাম প্রদর্শন
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 6),
                Text(
                  'প্রশ্ন প্রণেতা/স্যার: $creatorName',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (formattedStartTime.isNotEmpty)
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'শুরু: $formattedStartTime',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

            // পরীক্ষার সময়কাল (Duration) দেখানোর সেকশন
            if (durationText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'সময়কাল: $durationText',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            if (startTime.isNotEmpty && isActive)
              ExamCountdownCard(targetTimeStr: startTime),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'অধ্যায়: $displayChapter',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.indigo.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ক্লাস: ${test['class_name'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'বিষয়: ${test['subject_name'] ?? 'উল্লেখ নেই'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),

                      const SizedBox(height: 4),
                      Text(
                        'প্রশ্ন সংখ্যা: $questionCount টি',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                isActive
                    ? ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          'অংশগ্রহণ করুন',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: OutlinedButton(
                              onPressed: () => _showResultDialog(test),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.indigo,
                                side: BorderSide(color: Colors.indigo.shade200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'ফলাফল',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: OutlinedButton(
                              onPressed: () => _showRetestDialog(test),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.orange.shade800,
                                side: BorderSide(color: Colors.orange.shade300),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                '২য় সুযোগ',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExamCountdownCard extends StatefulWidget {
  final String targetTimeStr;

  const ExamCountdownCard({super.key, required this.targetTimeStr});

  @override
  State<ExamCountdownCard> createState() => _ExamCountdownCardState();
}

class _ExamCountdownCardState extends State<ExamCountdownCard> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateTimeLeft();
    });
  }

  void _calculateTimeLeft() {
    try {
      DateTime dt = DateTime.parse(widget.targetTimeStr);
      DateTime targetTime = DateTime(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
      );

      DateTime now = DateTime.now();
      Duration diff = targetTime.difference(now);

      if (diff.isNegative) {
        if (mounted) {
          setState(() {
            _isExpired = true;
            _timeLeft = Duration.zero;
          });
        }
        _timer?.cancel();
      } else {
        if (mounted) {
          setState(() {
            _isExpired = false;
            _timeLeft = diff;
          });
        }
      }
    } catch (e) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpired) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.timer_off, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Text(
              'পরীক্ষা শুরু হয়ে গেছে বা সময় শেষ!',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    int days = _timeLeft.inDays;
    int hours = _timeLeft.inHours % 24;
    int minutes = _timeLeft.inMinutes % 60;
    int seconds = _timeLeft.inSeconds % 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Row(
          children: [
            Icon(
              Icons.hourglass_bottom_rounded,
              size: 16,
              color: Colors.black54,
            ),
            SizedBox(width: 6),
            Text(
              'বাকি আছে:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Text(
          '${days > 0 ? '$days দিন ' : ''}${hours} ঘণ্টা ${minutes} মিনিট ${seconds} সেকেন্ড',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
      ],
    );
  }
}
