import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class StudentAttendancePageView extends StatefulWidget {
  final String academyId;
  final String teacherName;

  const StudentAttendancePageView({
    super.key,
    required this.academyId,
    required this.teacherName,
  });

  @override
  State<StudentAttendancePageView> createState() =>
      _StudentAttendancePageViewState();
}

class _StudentAttendancePageViewState extends State<StudentAttendancePageView> {
  final supabase = Supabase.instance.client;
  bool _isOnline = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _attendanceStatus = {};
  List<String> _classes = [];
  String _selectedClass = '';
  final String _currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // শেষ কে আপডেট করেছে তার নাম এবং গত ২ দিনের বিস্তারিত ডাটা
  String _lastUpdatedByTeacher = 'কেউ নয়';
  int _lastDay1Present = 0;
  int _lastDay1Absent = 0;
  String _lastDay1DateStr = '';
  double _lastDay1Percentage = 0.0;

  int _lastDay2Present = 0;
  int _lastDay2Absent = 0;
  String _lastDay2DateStr = '';
  double _lastDay2Percentage = 0.0;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initConnectivityAndCheck();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initConnectivityAndCheck() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    _updateConnectionStatus(connectivityResult);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      _updateConnectionStatus(results);
    });

    _fetchStudentsAndAttendance();
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    bool hasConnection = !results.contains(ConnectivityResult.none);
    if (_isOnline != hasConnection) {
      setState(() {
        _isOnline = hasConnection;
      });
      if (_isOnline) {
        _syncPendingDataToSupabase();
      }
    }
  }

  Future<void> _fetchStudentsAndAttendance() async {
    try {
      final response = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', widget.academyId);

      final List data = response as List;
      _students = data.map((e) => Map<String, dynamic>.from(e)).toList();

      Set<String> classSet = {};
      for (var student in _students) {
        String cName = student['class'] ?? student['class_name'] ?? 'অন্যান্য';
        classSet.add(cName);
      }
      _classes = classSet.toList();
      _classes.sort();

      if (_classes.isNotEmpty && _selectedClass.isEmpty) {
        _selectedClass = _classes.first;
      }

      await _loadAttendanceForCurrentClass();
    } catch (e) {
      Get.snackbar(
        "নোটিশ",
        "অফলাইন মোড বা নেটওয়ার্ক সমস্যা: $e",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  // বর্তমান সিলেক্টেড ক্লাসের হাজিরা ও কে আপডেট করেছে তা লোড করা
  Future<void> _loadAttendanceForCurrentClass() async {
    try {
      final attResponse = await supabase
          .from('student_attendance')
          .select('*')
          .eq('academy_id', widget.academyId)
          .eq('date', _currentDate)
          .eq('class_name', _selectedClass);

      _attendanceStatus.clear();

      List<Map<String, dynamic>> filteredStudents = _students.where((student) {
        String cName = student['class'] ?? student['class_name'] ?? 'অন্যান্য';
        return cName == _selectedClass;
      }).toList();

      for (var student in filteredStudents) {
        _attendanceStatus[student['id'].toString()] = 'Present';
      }

      if (attResponse != null && (attResponse as List).isNotEmpty) {
        _lastUpdatedByTeacher =
            attResponse[0]['updated_by_teacher'] ??
            attResponse[0]['teacher_name'] ??
            'কেউ নয়';

        for (var att in (attResponse as List)) {
          String sId = att['student_id']?.toString().trim() ?? '';
          String status = att['status']?.toString() ?? 'Present';

          for (var key in _attendanceStatus.keys) {
            if (key.trim() == sId) {
              _attendanceStatus[key] = status;
            }
          }
        }
      } else {
        _lastUpdatedByTeacher = 'আজ এখনো কেউ এন্ট্রি দেয়নি';
      }

      await _fetchPastDaysHistory();
    } catch (_) {
      _lastUpdatedByTeacher = 'তথ্য লোড হয়নি';
    } finally {
      if (mounted) {
        setState(
          () {},
        ); // শুধু ডেটা আসার পর উইজেট রিফ্রেশ করবে, সার্কেল দেখাবে না
      }
    }
  }

  Future<void> _fetchPastDaysHistory() async {
    try {
      DateTime now = DateTime.now();
      String day1 = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));
      String day2 = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 2)));

      _lastDay1DateStr = DateFormat(
        'dd MMM',
      ).format(now.subtract(const Duration(days: 1)));
      _lastDay2DateStr = DateFormat(
        'dd MMM',
      ).format(now.subtract(const Duration(days: 2)));

      final pastResponse = await supabase
          .from('student_attendance')
          .select('*')
          .eq('academy_id', widget.academyId)
          .inFilter('date', [day1, day2])
          .eq('class_name', _selectedClass);

      if (pastResponse != null) {
        List pastList = pastResponse as List;

        int p1 = 0, a1 = 0, p2 = 0, a2 = 0;

        for (var record in pastList) {
          String status = record['status']?.toString() ?? 'Present';
          String recordDate = record['date']?.toString() ?? '';

          if (recordDate == day1) {
            if (status == 'Present') {
              p1++;
            } else {
              a1++;
            }
          } else if (recordDate == day2) {
            if (status == 'Present') {
              p2++;
            } else {
              a2++;
            }
          }
        }

        _lastDay1Present = p1;
        _lastDay1Absent = a1;
        int total1 = p1 + a1;
        _lastDay1Percentage = total1 > 0 ? (p1 / total1) * 100 : 0.0;

        _lastDay2Present = p2;
        _lastDay2Absent = a2;
        int total2 = p2 + a2;
        _lastDay2Percentage = total2 > 0 ? (p2 / total2) * 100 : 0.0;
      }
    } catch (_) {}
  }

  Future<void> _syncPendingDataToSupabase() async {
    Get.snackbar(
      "অনлайн",
      "ইন্টারনেট সংযোগ পাওয়া গেছে, ডাটা সিঙ্ক করা হচ্ছে...",
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
    await _loadAttendanceForCurrentClass();
  }

  Future<void> _saveAttendance() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      List<Map<String, dynamic>> recordsToUpsert = [];

      List<Map<String, dynamic>> filteredStudents = _students.where((student) {
        String cName = student['class'] ?? student['class_name'] ?? 'অন্যান্য';
        return cName == _selectedClass;
      }).toList();

      int total = filteredStudents.length;
      int present = filteredStudents
          .where((s) => _attendanceStatus[s['id'].toString()] == 'Present')
          .length;
      double currentPercentage = total > 0 ? (present / total) * 100 : 0.0;

      for (var student in filteredStudents) {
        String sId = student['id'].toString();
        String status = _attendanceStatus[sId] ?? 'Present';

        recordsToUpsert.add({
          'academy_id': widget.academyId,
          'student_id': sId,
          'class_name': _selectedClass,
          'date': _currentDate,
          'status': status,
          'teacher_name': widget.teacherName,
          'updated_by_teacher': widget.teacherName,
          'attendance_percentage': currentPercentage,
          'is_synced': _isOnline,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (_isOnline) {
        await supabase
            .from('student_attendance')
            .upsert(recordsToUpsert, onConflict: 'academy_id,student_id,date');

        setState(() {
          _lastUpdatedByTeacher = widget.teacherName;
        });

        Navigator.pop(context);
        Get.snackbar(
          "সফল",
          "হাজিরা সফলভাবে সংরক্ষিত ও ক্লাসের পার্সেন্টেজ (${currentPercentage.toStringAsFixed(1)}%) আপডেট হয়েছে!",
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        Navigator.pop(context);
        Get.snackbar(
          "অফলাইন মোড",
          "ইন্টারনেট নেই! ডাটা লোকালি সংরক্ষিত হয়েছে, সংযোগ আসলে অটো সিঙ্ক হবে।",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Navigator.pop(context);
      Get.snackbar(
        "ত্রুটি",
        "হাজিরা সেভ করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredStudents = _students.where((student) {
      String cName = student['class'] ?? student['class_name'] ?? 'অন্যান্য';
      return cName == _selectedClass;
    }).toList();

    int totalStudents = filteredStudents.length;
    int presentCount = 0;
    int absentCount = 0;

    for (var student in filteredStudents) {
      String sId = student['id'].toString();
      if (_attendanceStatus[sId] == 'Absent') {
        absentCount++;
      } else {
        presentCount++;
      }
    }

    double todayPercentage = totalStudents > 0
        ? (presentCount / totalStudents) * 100
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Get.back(),
                          ),
                          const Text(
                            'হাজিরা ব্যবস্থাপনা',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedClass.isNotEmpty
                                ? _selectedClass
                                : null,
                            hint: const Text('ক্লাস বেছে নিন'),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.green,
                            ),
                            items: _classes.map((String className) {
                              return DropdownMenuItem<String>(
                                value: className,
                                child: Text(
                                  'ক্লাস: $className',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.green,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedClass = newValue;
                                  _loadAttendanceForCurrentClass();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // সামারি বক্স
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryItem(
                              'মোট',
                              '$totalStudents',
                              Colors.blue.shade800,
                            ),
                            _buildSummaryItem(
                              'উপস্থিত',
                              '$presentCount',
                              Colors.green.shade800,
                            ),
                            _buildSummaryItem(
                              'অনুপস্থিত',
                              '$absentCount',
                              Colors.red.shade800,
                            ),
                            _buildSummaryItem(
                              'হার (%)',
                              '${todayPercentage.toStringAsFixed(1)}%',
                              Colors.purple.shade800,
                            ),
                          ],
                        ),
                        const Divider(height: 14, thickness: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$_lastDay1DateStr: উপ:${_lastDay1Present}, অনু:${_lastDay1Absent} (${_lastDay1Percentage.toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              '$_lastDay2DateStr: উপ:${_lastDay2Present}, অনু:${_lastDay2Absent} (${_lastDay2Percentage.toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 14,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'সর্বশেষ আপডেট করেছেন: $_lastUpdatedByTeacher',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            Expanded(
              child: filteredStudents.isEmpty
                  ? const Center(
                      child: Text(
                        'এই ক্লাসে কোনো শিক্ষার্থী নেই।',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredStudents.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final student = filteredStudents[index];
                        String sId = student['id'].toString();
                        String studentName =
                            student['full_name'] ?? student['name'] ?? 'নামহীন';
                        String roll = student['roll']?.toString() ?? 'নেই';
                        String status = _attendanceStatus[sId] ?? 'Present';
                        bool isPresent = (status == 'Present');

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey.shade200,
                              child: ClipOval(
                                child:
                                    (student['image_url'] != null &&
                                        student['image_url']
                                            .toString()
                                            .isNotEmpty)
                                    ? Image.network(
                                        student['image_url'],
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return const Icon(
                                                Icons.person,
                                                color: Colors.grey,
                                              );
                                            },
                                      )
                                    : const Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                      ),
                              ),
                            ),
                            title: Text(
                              studentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text('রোল: $roll'),
                            trailing: InkWell(
                              onTap: () {
                                setState(() {
                                  _attendanceStatus[sId] = isPresent
                                      ? 'Absent'
                                      : 'Present';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? Colors.green
                                      : Colors.red.shade400,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isPresent ? 'উপস্থিত' : 'অনুপস্থিত',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: ElevatedButton(
          onPressed: _saveAttendance,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'হাজিরা সংরক্ষণ ও পার্সেন্টেজ আপডেট করুন',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String count, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          count,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
