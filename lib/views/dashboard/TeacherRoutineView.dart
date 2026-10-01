import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherRoutineView extends StatefulWidget {
  final String academyId;
  final String teacherId;
  final String teacherName;

  const TeacherRoutineView({
    Key? key,
    required this.academyId,
    required this.teacherId,
    required this.teacherName,
  }) : super(key: key);

  @override
  State<TeacherRoutineView> createState() => _TeacherRoutineViewState();
}

class _TeacherRoutineViewState extends State<TeacherRoutineView> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;
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

  final List<String> daysOrder = [
    'শনিবার',
    'রবিবার',
    'সোমবার',
    'মঙ্গলবার',
    'বুধবার',
    'বৃহস্পতিবার',
    'শুক্রবার',
  ];

  @override
  void initState() {
    super.initState();
    _fetchTeacherRoutines();

    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
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

  Future<void> _fetchTeacherRoutines() async {
    try {
      final response = await supabase
          .from('class_routines')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('teacher_id', widget.teacherId);

      if (response != null) {
        setState(() {
          routines = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching teacher routines: $e");
      setState(() {
        isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    String todayBengali = _weekdaysMap[_now.weekday] ?? 'শনিবার';
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
      int remainingMin = endMin - currentMinutes;
      if (remainingMin > 0) {
        remainingTimeText = 'শেষ হতে আর $remainingMin মিনিট বাকি';
      } else {
        remainingTimeText = 'ক্লাস শেষের পথে';
      }
    }

    // দিনগুলোর তালিকা সাজানো যাতে আজকের দিনটি সবার আগে থাকে
    List<String> sortedDays = [todayBengali];
    for (var day in daysOrder) {
      if (day != todayBengali) {
        sortedDays.add(day);
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('${widget.teacherName}-এর রুটিন'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : RefreshIndicator(
              onRefresh: _fetchTeacherRoutines,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ১. উপরের স্মার্ট বক্স (রানিং ও নেক্সট ক্লাস)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.teal.shade800, Colors.teal.shade500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'আজ: $todayBengali',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 20),

                          // রানিং ক্লাস সেকশন
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
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              remainingTimeText,
                                              style: const TextStyle(
                                                color: Colors.black87,
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

                          // নেক্সট ক্লাস সেকশন
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
                    const SizedBox(height: 24),

                    // ২. নিচের সেকশন: সাপ্তাহিক রুটিন (আজকের দিন আগে, বাকি দিনগুলো ক্লিক করলে খুলবে)
                    const Text(
                      'সাপ্তাহিক ক্লাসের রুটিন',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),

                    routines.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30.0),
                              child: Text(
                                'আপনার কোনো রুটিন পাওয়া যায়নি।',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sortedDays.length,
                            itemBuilder: (context, dayIndex) {
                              String dayName = sortedDays[dayIndex];
                              bool isToday = (dayName == todayBengali);

                              List<Map<String, dynamic>> dayRoutines = routines
                                  .where((r) {
                                    return (r['day'] ?? '') == dayName;
                                  })
                                  .toList();

                              if (dayRoutines.isEmpty)
                                return const SizedBox.shrink();

                              // পিরিয়ডের সময় অনুযায়ী সিকোয়েন্স সাজানো
                              dayRoutines.sort((a, b) {
                                int timeA = _timeToMinutes(
                                  a['start_time'] ?? '00:00 AM',
                                );
                                int timeB = _timeToMinutes(
                                  b['start_time'] ?? '00:00 AM',
                                );
                                return timeA.compareTo(timeB);
                              });

                              // আজকের দিন হলে বাই-ডিফল্ট ওপেন থাকবে, অন্যদিনগুলো বন্ধ থাকবে (ExpansionTile)
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isToday
                                        ? Colors.teal.shade300
                                        : Colors.grey.shade300,
                                    width: isToday ? 1.5 : 1,
                                  ),
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded:
                                      isToday, // আজকের দিন খোলা থাকবে
                                  leading: Icon(
                                    Icons.calendar_today,
                                    color: isToday
                                        ? Colors.teal
                                        : Colors.grey.shade600,
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        dayName,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isToday
                                              ? Colors.teal.shade800
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (isToday) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade100,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'আজ',
                                            style: TextStyle(
                                              color: Colors.teal,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    'মোট ক্লাস: ${dayRoutines.length}টি',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        12,
                                      ),
                                      child: Column(
                                        children: dayRoutines.map((item) {
                                          String className =
                                              item['class_name'] ?? '';
                                          String subject =
                                              item['subject'] ??
                                              'নির্দিষ্ট নেই';
                                          String periodName =
                                              item['period_name'] ?? '';
                                          String startTime =
                                              item['start_time'] ?? '';
                                          String endTime =
                                              item['end_time'] ?? '';
                                          bool isOff = item['is_off'] ?? false;

                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: isOff
                                                  ? Colors.red.shade50
                                                  : Colors.grey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isOff
                                                    ? Colors.red.shade200
                                                    : Colors.grey.shade200,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        '$periodName ($startTime - $endTime)',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                          color: isOff
                                                              ? Colors.red
                                                              : Colors
                                                                    .teal
                                                                    .shade900,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        'ক্লাস: $className | বিষয়: $subject',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (isOff)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: const Text(
                                                      'বন্ধ',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
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
}
