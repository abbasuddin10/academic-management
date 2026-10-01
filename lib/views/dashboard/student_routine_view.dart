import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class StudentRoutineView extends StatefulWidget {
  final String academyId;
  final String className;

  const StudentRoutineView({
    super.key,
    required this.academyId,
    required this.className,
  });

  @override
  State<StudentRoutineView> createState() => _StudentRoutineViewState();
}

class _StudentRoutineViewState extends State<StudentRoutineView> {
  bool hasInternet = true;
  List<Map<String, dynamic>> routineList = [];
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

  final List<String> _orderedDays = [
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
    _checkInternetAndFetchRoutine();

    // প্রতি ১ সেকেন্ড পরপর টাইমার রান করবে যাতে রানিং ক্লাসের লাইভ কাউন্টডাউন দেখায়
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

  Future<void> _checkInternetAndFetchRoutine() async {
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
      await fetchRoutine();
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

  Future<void> fetchRoutine() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('class_routines')
          .select()
          .eq('academy_id', widget.academyId)
          .ilike('class_name', widget.className.trim());

      if (mounted) {
        setState(() {
          routineList = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print("Error fetching routine: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    String todayBengali = _weekdaysMap[_now.weekday] ?? 'শনিবার';
    int currentTotalSeconds =
        (_now.hour * 3600) + (_now.minute * 60) + _now.second;
    int currentMinutes = _now.hour * 60 + _now.minute;

    // আজকের রুটিন ফিল্টার ও সময় অনুযায়ী সাজানো
    List<Map<String, dynamic>> todayRoutines = routineList.where((r) {
      return (r['day'] ?? '') == todayBengali && !(r['is_off'] ?? false);
    }).toList();

    todayRoutines.sort((a, b) {
      int timeA = _timeToMinutes(a['start_time'] ?? a['time'] ?? '00:00 AM');
      int timeB = _timeToMinutes(b['start_time'] ?? b['time'] ?? '00:00 AM');
      return timeA.compareTo(timeB);
    });

    Map<String, dynamic>? currentClass;
    Map<String, dynamic>? nextClass;

    for (var r in todayRoutines) {
      int startMin = _timeToMinutes(r['start_time'] ?? r['time'] ?? '');
      int endMin = _timeToMinutes(r['end_time'] ?? '');

      if (currentMinutes >= startMin &&
          (endMin == 0 || currentMinutes <= endMin)) {
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

    // দিনগুলোকে সাজানো যাতে আজকের দিনটি সবার উপরে থাকে
    List<String> sortedDays = [
      todayBengali,
      ..._orderedDays.where((day) => day != todayBengali),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text('${widget.className} - ক্লাস রুটিন'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
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
              onRefresh: _checkInternetAndFetchRoutine,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ১. উপরের সেকশন: রানিং ও পরবর্তী ক্লাস
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3F51B5), Color(0xFF1A237E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                                color: Colors.white,
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
                                          ? '${currentClass['subject'] ?? 'বিষয় নেই'} (${currentClass['teacher_name'] ?? 'শিক্ষক নেই'})'
                                          : 'এই মুহূর্তে কোনো ক্লাস চলছে না',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (currentClass != null)
                                      Text(
                                        'সময়: ${currentClass['start_time'] ?? currentClass['time'] ?? ''} - ${currentClass['end_time'] ?? ''}',
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
                          const Divider(color: Colors.white30, height: 20),
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
                                          ? 'সময়: ${nextClass['start_time'] ?? nextClass['time'] ?? ''} | ${nextClass['subject'] ?? 'বিষয় নেই'} (${nextClass['teacher_name'] ?? 'শিক্ষক নেই'})'
                                          : 'আজ আর কোনো ক্লাস নেই',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
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
                    const Text(
                      'সকল দিনের রুটিন',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    routineList.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(top: 30.0),
                            child: Center(
                              child: Text(
                                'এই ক্লাসের জন্য কোনো রুটিন পাওয়া যায়নি।',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sortedDays.length,
                            itemBuilder: (context, index) {
                              String day = sortedDays[index];

                              // উক্ত বারের রুটিনগুলো ফিল্টার করা
                              List<Map<String, dynamic>> dayRoutines =
                                  routineList.where((r) {
                                    return (r['day'] ?? '') == day;
                                  }).toList();

                              if (dayRoutines.isEmpty)
                                return const SizedBox.shrink();

                              // সময় অনুযায়ী সাজানো
                              dayRoutines.sort((a, b) {
                                int timeA = _timeToMinutes(
                                  a['start_time'] ?? a['time'] ?? '00:00 AM',
                                );
                                int timeB = _timeToMinutes(
                                  b['start_time'] ?? b['time'] ?? '00:00 AM',
                                );
                                return timeA.compareTo(timeB);
                              });

                              bool isToday = (day == todayBengali);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: isToday
                                      ? Border.all(
                                          color: Colors.indigo,
                                          width: 1.5,
                                        )
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.1),
                                      spreadRadius: 1,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded:
                                      isToday, // আজকের দিনটি ডিফল্টভাবে খোলা থাকবে, বাকিগুলো বন্ধ
                                  shape: const RoundedRectangleBorder(
                                    side: BorderSide.none,
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        day,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isToday
                                              ? Colors.indigo
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
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'আজ',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    'মোট ক্লাস: ${dayRoutines.length}টি',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  children: dayRoutines.map((routine) {
                                    String timeText = '';
                                    if (routine['start_time'] != null &&
                                        routine['end_time'] != null) {
                                      timeText =
                                          '${routine['start_time']} - ${routine['end_time']}';
                                    } else if (routine['time'] != null) {
                                      timeText = routine['time'].toString();
                                    }

                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'বিষয়: ${routine['subject'] ?? 'তথ্য নেই'}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              if (timeText.isNotEmpty)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.indigo.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    timeText,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.indigo,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'শিক্ষক: ${routine['teacher_name'] ?? 'তথ্য নেই'}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
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
}
