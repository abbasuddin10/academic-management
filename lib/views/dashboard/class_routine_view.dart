import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClassRoutineView extends StatefulWidget {
  final String academyId;

  const ClassRoutineView({super.key, required this.academyId});

  @override
  State<ClassRoutineView> createState() => _ClassRoutineViewState();
}

class _ClassRoutineViewState extends State<ClassRoutineView> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> teachers = [];
  List<String> availableClasses = [];

  final List<String> days = [
    'শনিবার',
    'রবিবার',
    'সোমবার',
    'মঙ্গলবার',
    'বুধবার',
    'বৃহস্পতিবার',
    'শুক্রবার',
  ];

  final Map<String, List<Map<String, String>>> dayPeriodsMap = {
    'শনিবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'রবিবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'সোমবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'মঙ্গলবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'বুধবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'বৃহস্পতিবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
    'শুক্রবার': [
      {'name': '১ম পিরিয়ড', 'startTime': '১০:০০ AM', 'endTime': '১০:৪৫ AM'},
      {'name': '২য় পিরিয়ড', 'startTime': '১০:৪৫ AM', 'endTime': '১১:৩০ AM'},
    ],
  };

  final Map<String, String> routineAssignments = {};
  final Map<String, String> slotClassMap = {};
  final Map<String, bool> classOffMap = {};
  final Map<String, TextEditingController> subjectControllers = {};

  List<Map<String, dynamic>> savedRoutines = [];
  bool isLoading = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAcademyStaffAndClasses().then((_) {
      _fetchRoutines();
    });
  }

  @override
  void dispose() {
    for (var controller in subjectControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAcademyStaffAndClasses() async {
    setState(() => isLoading = true);
    try {
      final usersResponse = await supabase
          .from('users')
          .select('id, full_name, role, academy_id')
          .eq('academy_id', widget.academyId)
          .inFilter('role', ['teacher', 'super_admin']);

      List<Map<String, dynamic>> fetchedStaff = [];
      if (usersResponse != null) {
        for (var item in (usersResponse as List)) {
          String name = item['full_name'] ?? '';
          String id = item['id'] ?? '';
          if (name.isNotEmpty && id.isNotEmpty) {
            fetchedStaff.add({'id': id, 'name': name});
          }
        }
      }

      final studentsResponse = await supabase
          .from('students')
          .select('class')
          .eq('academy_id', widget.academyId);

      Set<String> fetchedClasses = {};
      if (studentsResponse != null) {
        for (var item in (studentsResponse as List)) {
          String className = item['class']?.toString().trim() ?? '';
          if (className.isNotEmpty) {
            fetchedClasses.add(className);
          }
        }
      }

      setState(() {
        teachers = fetchedStaff;
        availableClasses = fetchedClasses.isNotEmpty
            ? fetchedClasses.toList()
            : ['পঞ্চম শ্রেণি', 'ষষ্ঠ শ্রেণি', 'সপ্তম শ্রেণি', 'অষ্টম শ্রেণি'];
      });
    } catch (e) {
      debugPrint("Error loading staff data: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchRoutines() async {
    try {
      final response = await supabase
          .from('class_routines')
          .select()
          .eq('academy_id', widget.academyId);

      setState(() {
        savedRoutines = List<Map<String, dynamic>>.from(response);

        for (var r in savedRoutines) {
          String day = r['day'];
          String periodName = r['period_name'];
          String className = r['class_name'];
          String teacherId = r['teacher_id'] ?? '';
          String subject = r['subject'] ?? '';
          bool isOff = r['is_off'] ?? false;

          int classIndex = availableClasses.indexOf(className);
          if (classIndex != -1) {
            List<Map<String, String>> periods = dayPeriodsMap[day] ?? [];
            int periodIndex = periods.indexWhere(
              (p) => p['name'] == periodName,
            );

            if (periodIndex != -1) {
              String slotKey = "${day}_${periodIndex}_${classIndex}";
              slotClassMap[slotKey] = className;

              String assignmentKey = "${day}_${periodName}_${classIndex}";
              if (teacherId.isNotEmpty) {
                routineAssignments[assignmentKey] = teacherId;
              }

              String offKey = "${day}_${periodName}_${className}";
              classOffMap[offKey] = isOff;

              if (!subjectControllers.containsKey(assignmentKey)) {
                subjectControllers[assignmentKey] = TextEditingController(
                  text: subject,
                );
              } else {
                subjectControllers[assignmentKey]!.text = subject;
              }
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Error fetching routines: $e");
    }
  }

  Future<void> _saveFullRoutine() async {
    setState(() => isSaving = true);
    try {
      List<Map<String, dynamic>> routinesToUpsert = [];

      for (var day in days) {
        List<Map<String, String>> periods = dayPeriodsMap[day] ?? [];
        for (int periodIndex = 0; periodIndex < periods.length; periodIndex++) {
          var period = periods[periodIndex];
          String periodName = period['name'] ?? '';
          String startTime = period['startTime'] ?? '';
          String endTime = period['endTime'] ?? '';

          for (
            int slotIndex = 0;
            slotIndex < availableClasses.length;
            slotIndex++
          ) {
            String slotKey = "${day}_${periodIndex}_${slotIndex}";
            String selectedClass =
                slotClassMap[slotKey] ?? availableClasses[slotIndex];

            String assignmentKey = "${day}_${periodName}_${slotIndex}";
            String? teacherId = routineAssignments[assignmentKey];
            String subject =
                subjectControllers[assignmentKey]?.text.trim() ?? '';

            String offKey = "${day}_${periodName}_${selectedClass}";
            bool isOff = classOffMap[offKey] ?? false;

            String? validTeacherId;
            String teacherName = '';

            if (teacherId != null && teacherId.isNotEmpty) {
              final matchedTeacher = teachers.firstWhere(
                (t) => t['id'].toString() == teacherId.toString(),
                orElse: () => {},
              );

              if (matchedTeacher.isNotEmpty) {
                validTeacherId = matchedTeacher['id'].toString();
                teacherName = matchedTeacher['name'] ?? '';
              }
            }

            bool hasTeacher =
                validTeacherId != null && validTeacherId.isNotEmpty;
            bool hasSubject = subject.isNotEmpty;

            if (hasTeacher || hasSubject || isOff) {
              routinesToUpsert.add({
                'academy_id': widget.academyId,
                'day': day,
                'period_name': periodName,
                'start_time': startTime,
                'end_time': endTime,
                'class_name': selectedClass,
                'teacher_id': hasTeacher ? validTeacherId : null,
                'teacher_name': teacherName,
                'subject': subject,
                'is_off': isOff,
              });
            }
          }
        }
      }

      if (routinesToUpsert.isNotEmpty) {
        await supabase
            .from('class_routines')
            .upsert(
              routinesToUpsert,
              onConflict: 'academy_id,day,period_name,class_name',
            );

        await _fetchRoutines();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('রুটিন সফলভাবে সংরক্ষণ করা হয়েছে!'),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      debugPrint("Error saving full routine: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('রুটিন সংরক্ষণ করতে সমস্যা হয়েছে: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> _deleteFromSupabase(
    String day,
    String periodName,
    String className,
  ) async {
    try {
      await supabase
          .from('class_routines')
          .delete()
          .eq('academy_id', widget.academyId)
          .eq('day', day)
          .eq('period_name', periodName)
          .eq('class_name', className);
    } catch (e) {
      debugPrint("Error deleting routine from Supabase: $e");
    }
  }

  // শিক্ষক পরিবর্তনের জন্য এক্সচেঞ্জ ডায়ালগ বক্স
  void _showTeacherExchangeDialog(
    String day,
    String periodName,
    int currentSlotIndex,
    String currentTeacherId,
  ) {
    String? selectedNewTeacherId = currentTeacherId.isNotEmpty
        ? currentTeacherId
        : null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('শিক্ষক পরিবর্তন বা এক্সচেঞ্জ করুন'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return DropdownButtonFormField<String>(
                value:
                    teachers.any(
                      (t) => t['id'].toString() == selectedNewTeacherId,
                    )
                    ? selectedNewTeacherId
                    : null,
                hint: const Text('সকল শিক্ষক থেকে সিলেক্ট করুন'),
                isExpanded: true,
                items: teachers.map((tch) {
                  String tId = tch['id'].toString();
                  String tName = tch['name'].toString();
                  return DropdownMenuItem<String>(
                    value: tId,
                    child: Text(tName),
                  );
                }).toList(),
                onChanged: (String? val) {
                  setDialogState(() {
                    selectedNewTeacherId = val;
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('বাতিল'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (selectedNewTeacherId != null) {
                    for (int sIdx = 0; sIdx < availableClasses.length; sIdx++) {
                      if (sIdx != currentSlotIndex) {
                        String otherKey = "${day}_${periodName}_${sIdx}";
                        if (routineAssignments[otherKey] ==
                            selectedNewTeacherId) {
                          routineAssignments.remove(otherKey);
                        }
                      }
                    }

                    String targetKey =
                        "${day}_${periodName}_${currentSlotIndex}";
                    routineAssignments[targetKey] = selectedNewTeacherId!;
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('নিশ্চিত করুন'),
            ),
          ],
        );
      },
    );
  }

  // সময় সিলেক্ট করার জন্য হেল্পার ফাংশন (টাইম পিকার উইজেট)
  Future<String?> _selectTimeWithAmPm(
    BuildContext context,
    String initialTime,
  ) async {
    // ইনিশিয়াল টাইম থেকে টাইম পার্স করা
    int initialHour = 10;
    int initialMinute = 0;
    bool isPm = false;

    try {
      var parts = initialTime.split(' ');
      var timeParts = parts[0].split(':');
      initialHour = int.parse(timeParts[0]);
      initialMinute = int.parse(timeParts[1]);
      isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && initialHour != 12) {
        // TimeOfDay-এর জন্য ২৪ ঘণ্টার ফরম্যাটে কনভার্ট
      }
    } catch (_) {}

    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: isPm && initialHour != 12
            ? initialHour + 12
            : (!isPm && initialHour == 12 ? 0 : initialHour),
        minute: initialMinute,
      ),
    );

    if (pickedTime != null) {
      final localizations = MaterialLocalizations.of(context);
      final formattedTimeOfDay = localizations.formatTimeOfDay(
        pickedTime,
        alwaysUse24HourFormat: false,
      );
      return formattedTimeOfDay; // যেমন: "10:00 PM" বা "10:00 AM"
    }
    return null;
  }

  void _showAddPeriodDialog(String day) {
    TextEditingController nameController = TextEditingController(
      text: '${dayPeriodsMap[day]!.length + 1}ম পিরিয়ড',
    );
    TextEditingController startTimeController = TextEditingController(
      text: '10:00 PM',
    );
    TextEditingController endTimeController = TextEditingController(
      text: '11:45 PM',
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('$day নতুন পিরিয়ড যোগ করুন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'পিরিয়ডের নাম',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startTimeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'শুরুর সময় (AM/PM সহ)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          onPressed: () async {
                            String? newTime = await _selectTimeWithAmPm(
                              context,
                              startTimeController.text,
                            );
                            if (newTime != null) {
                              setDialogState(() {
                                startTimeController.text = newTime;
                              });
                            }
                          },
                        ),
                      ),
                      onTap: () async {
                        String? newTime = await _selectTimeWithAmPm(
                          context,
                          startTimeController.text,
                        );
                        if (newTime != null) {
                          setDialogState(() {
                            startTimeController.text = newTime;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endTimeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'শেষের সময় (AM/PM সহ)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          onPressed: () async {
                            String? newTime = await _selectTimeWithAmPm(
                              context,
                              endTimeController.text,
                            );
                            if (newTime != null) {
                              setDialogState(() {
                                endTimeController.text = newTime;
                              });
                            }
                          },
                        ),
                      ),
                      onTap: () async {
                        String? newTime = await _selectTimeWithAmPm(
                          context,
                          endTimeController.text,
                        );
                        if (newTime != null) {
                          setDialogState(() {
                            endTimeController.text = newTime;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বাতিল'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      setState(() {
                        dayPeriodsMap[day]!.add({
                          'name': nameController.text,
                          'startTime': startTimeController.text,
                          'endTime': endTimeController.text,
                        });
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('যোগ করুন'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditPeriodDialog(
    String day,
    int index,
    Map<String, String> currentPeriodData,
  ) {
    TextEditingController nameController = TextEditingController(
      text: currentPeriodData['name'],
    );
    TextEditingController startTimeController = TextEditingController(
      text: currentPeriodData['startTime'],
    );
    TextEditingController endTimeController = TextEditingController(
      text: currentPeriodData['endTime'],
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('পিরিয়ড ও সময় এডিট করুন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'পিরিয়ডের নাম',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startTimeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'শুরুর সময় (AM/PM সহ)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          onPressed: () async {
                            String? newTime = await _selectTimeWithAmPm(
                              context,
                              startTimeController.text,
                            );
                            if (newTime != null) {
                              setDialogState(() {
                                startTimeController.text = newTime;
                              });
                            }
                          },
                        ),
                      ),
                      onTap: () async {
                        String? newTime = await _selectTimeWithAmPm(
                          context,
                          startTimeController.text,
                        );
                        if (newTime != null) {
                          setDialogState(() {
                            startTimeController.text = newTime;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endTimeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'শেষের সময় (AM/PM সহ)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          onPressed: () async {
                            String? newTime = await _selectTimeWithAmPm(
                              context,
                              endTimeController.text,
                            );
                            if (newTime != null) {
                              setDialogState(() {
                                endTimeController.text = newTime;
                              });
                            }
                          },
                        ),
                      ),
                      onTap: () async {
                        String? newTime = await _selectTimeWithAmPm(
                          context,
                          endTimeController.text,
                        );
                        if (newTime != null) {
                          setDialogState(() {
                            endTimeController.text = newTime;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বাতিল'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      setState(() {
                        dayPeriodsMap[day]![index] = {
                          'name': nameController.text,
                          'startTime': startTimeController.text,
                          'endTime': endTimeController.text,
                        };
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('সংরক্ষণ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(
    String day,
    int periodIndex,
    String periodName,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('পিরিয়ড ডিলিট নিশ্চিত করুন'),
          content: const Text(
            'আপনি কি সত্যিই এই পিরিয়ডটি রুটিন থেকে মুছে ফেলতে চান?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('না'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  dayPeriodsMap[day]!.removeAt(periodIndex);
                });
                for (var cls in availableClasses) {
                  _deleteFromSupabase(day, periodName, cls);
                }
                Navigator.pop(context);
              },
              child: const Text('হ্যাঁ, ডিলিট করুন'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('রুটিন তৈরি করুন'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.teal,
              ),
              onPressed: isSaving ? null : _saveFullRoutine,
              icon: isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 16),
              label: Text(isSaving ? 'সেভ হচ্ছে...' : 'সেভ করুন'),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.teal.shade50,
                  width: double.infinity,
                  child: Text(
                    'মোট শিক্ষক/এডমিন: ${teachers.length} জন | মোট ক্লাস: ${availableClasses.length}টি',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: days.length,
                    itemBuilder: (context, dayIndex) {
                      String day = days[dayIndex];
                      List<Map<String, String>> periods =
                          dayPeriodsMap[day] ?? [];

                      return ExpansionTile(
                        initiallyExpanded: dayIndex == 0,
                        title: Text(
                          day,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                            fontSize: 16,
                          ),
                        ),
                        children: [
                          ...periods.asMap().entries.map((entry) {
                            int periodIndex = entry.key;
                            Map<String, String> periodData = entry.value;
                            String periodName = periodData['name'] ?? '';
                            String startTime = periodData['startTime'] ?? '';
                            String endTime = periodData['endTime'] ?? '';

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
                                        onTap: () => _showEditPeriodDialog(
                                          day,
                                          periodIndex,
                                          periodData,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              '$periodName ($startTime - $endTime)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.edit,
                                              size: 14,
                                              color: Colors.teal,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _showDeleteConfirmationDialog(
                                              day,
                                              periodIndex,
                                              periodName,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 8),
                                  ...availableClasses.asMap().entries.map((
                                    classEntry,
                                  ) {
                                    int slotIndex = classEntry.key;

                                    String slotKey =
                                        "${day}_${periodIndex}_${slotIndex}";
                                    String selectedClass =
                                        slotClassMap[slotKey] ??
                                        (availableClasses.isNotEmpty
                                            ? availableClasses[slotIndex %
                                                  availableClasses.length]
                                            : '');

                                    String assignmentKey =
                                        "${day}_${periodName}_${slotIndex}";
                                    String? assignedTeacherId =
                                        routineAssignments[assignmentKey];

                                    String offKey =
                                        "${day}_${periodName}_${selectedClass}";
                                    bool isClassOff =
                                        classOffMap[offKey] ?? false;

                                    if (!subjectControllers.containsKey(
                                      assignmentKey,
                                    )) {
                                      subjectControllers[assignmentKey] =
                                          TextEditingController();
                                    }
                                    TextEditingController subjectController =
                                        subjectControllers[assignmentKey]!;

                                    bool hasTeacher =
                                        assignedTeacherId != null &&
                                        assignedTeacherId.isNotEmpty;

                                    Set<String> assignedTeachersInThisPeriod =
                                        {};
                                    for (
                                      int sIdx = 0;
                                      sIdx < availableClasses.length;
                                      sIdx++
                                    ) {
                                      if (sIdx != slotIndex) {
                                        String checkKey =
                                            "${day}_${periodName}_${sIdx}";
                                        if (routineAssignments.containsKey(
                                          checkKey,
                                        )) {
                                          assignedTeachersInThisPeriod.add(
                                            routineAssignments[checkKey]!,
                                          );
                                        }
                                      }
                                    }

                                    List<Map<String, dynamic>>
                                    availableTeachersForDropdown = teachers
                                        .where((tch) {
                                          String tId = tch['id'].toString();
                                          if (tId == assignedTeacherId)
                                            return true;
                                          return !assignedTeachersInThisPeriod
                                              .contains(tId);
                                        })
                                        .toList();

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4.0,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 75,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade50,
                                                border: Border.all(
                                                  color: Colors.teal.shade200,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value:
                                                      availableClasses.contains(
                                                        selectedClass,
                                                      )
                                                      ? selectedClass
                                                      : null,
                                                  isExpanded: true,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal,
                                                  ),
                                                  items: availableClasses.map((
                                                    String className,
                                                  ) {
                                                    return DropdownMenuItem<
                                                      String
                                                    >(
                                                      value: className,
                                                      child: Text(className),
                                                    );
                                                  }).toList(),
                                                  onChanged: (String? newClass) {
                                                    if (newClass != null) {
                                                      setState(() {
                                                        slotClassMap[slotKey] =
                                                            newClass;
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: isClassOff
                                                ? Container(
                                                    height: 38,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade50,
                                                      border: Border.all(
                                                        color:
                                                            Colors.red.shade200,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: const Text(
                                                      'ক্লাস বন্ধ',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  )
                                                : Container(
                                                    height: 38,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: DropdownButtonHideUnderline(
                                                            child: DropdownButton<String>(
                                                              value:
                                                                  assignedTeacherId,
                                                              hint: const Text(
                                                                'শিক্ষক সিলেক্ট',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .red,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                              isExpanded: true,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .green
                                                                    .shade700,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                              items: availableTeachersForDropdown.map((
                                                                tch,
                                                              ) {
                                                                String
                                                                tId = tch['id']
                                                                    .toString();
                                                                String
                                                                tName = tch['name']
                                                                    .toString();
                                                                return DropdownMenuItem<
                                                                  String
                                                                >(
                                                                  value: tId,
                                                                  child: Text(
                                                                    tName,
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                );
                                                              }).toList(),
                                                              onChanged:
                                                                  (
                                                                    String?
                                                                    newTeacherId,
                                                                  ) {
                                                                    setState(() {
                                                                      if (newTeacherId !=
                                                                          null) {
                                                                        for (
                                                                          int
                                                                          sIdx =
                                                                              0;
                                                                          sIdx <
                                                                              availableClasses.length;
                                                                          sIdx++
                                                                        ) {
                                                                          if (sIdx !=
                                                                              slotIndex) {
                                                                            String
                                                                            otherKey =
                                                                                "${day}_${periodName}_${sIdx}";
                                                                            if (routineAssignments[otherKey] ==
                                                                                newTeacherId) {
                                                                              routineAssignments.remove(
                                                                                otherKey,
                                                                              );
                                                                            }
                                                                          }
                                                                        }
                                                                        routineAssignments[assignmentKey] =
                                                                            newTeacherId;
                                                                      } else {
                                                                        routineAssignments.remove(
                                                                          assignmentKey,
                                                                        );
                                                                      }
                                                                    });
                                                                  },
                                                            ),
                                                          ),
                                                        ),
                                                        IconButton(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                          icon: const Icon(
                                                            Icons.swap_horiz,
                                                            size: 18,
                                                            color: Colors.teal,
                                                          ),
                                                          tooltip:
                                                              'শিক্ষক এক্সচেンジ করুন',
                                                          onPressed: () =>
                                                              _showTeacherExchangeDialog(
                                                                day,
                                                                periodName,
                                                                slotIndex,
                                                                assignedTeacherId ??
                                                                    '',
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                          ),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 70,
                                            height: 38,
                                            child: TextField(
                                              controller: subjectController,
                                              enabled: !isClassOff,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: isClassOff
                                                    ? 'বন্ধ'
                                                    : 'বিষয়',
                                                hintStyle: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 0,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  borderSide: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              isClassOff
                                                  ? Icons.toggle_on
                                                  : Icons.toggle_off,
                                              color: isClassOff
                                                  ? Colors.red
                                                  : Colors.grey,
                                              size: 24,
                                            ),
                                            tooltip: 'ছুটি অন/অফ করুন',
                                            onPressed: () {
                                              setState(() {
                                                classOffMap[offKey] =
                                                    !isClassOff;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            );
                          }).toList(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade50,
                                foregroundColor: Colors.teal,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: BorderSide(color: Colors.teal.shade200),
                                ),
                              ),
                              onPressed: () => _showAddPeriodDialog(day),
                              icon: const Icon(Icons.add, size: 16),
                              label: Text('$day নতুন পিরিয়ড যোগ করুন'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
