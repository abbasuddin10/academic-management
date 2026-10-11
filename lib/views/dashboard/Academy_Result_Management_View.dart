import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcademyResultManagementView extends StatefulWidget {
  final String academyId;
  final String? currentUserId;
  final String? currentUserName;

  const AcademyResultManagementView({
    super.key,
    required this.academyId,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<AcademyResultManagementView> createState() =>
      _AcademyResultManagementViewState();
}

class _AcademyResultManagementViewState
    extends State<AcademyResultManagementView> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool isLoadingClasses = false;
  bool isLoadingExams = false;
  bool isLoadingStudents = false;

  // ক্লাসের তালিকা এবং সিলেক্টেড ক্লাস
  List<String> availableClasses = [];
  String? selectedClass;

  // পরীক্ষার তালিকা এবং সিলেক্টেড পরীক্ষা
  List<String> availableExams = [];
  String? selectedExam;

  // ছাত্রছাত্রীদের তালিকা
  List<Map<String, dynamic>> studentsList = [];

  @override
  void initState() {
    super.initState();
    _loadAcademyClasses();
    _loadAcademyExams();
  }

  // Supabase থেকে নির্দিষ্ট একাডেমির ক্লাসগুলো লোড করা
  Future<void> _loadAcademyClasses() async {
    setState(() => isLoadingClasses = true);
    try {
      final response = await supabase
          .from(
            'exam_routines',
          ) // অথবা আপনার স্টুডেন্ট/ক্লাস টেবিল থাকলে তার নাম দিতে পারেন
          .select('class_name')
          .eq('academy_id', widget.academyId);

      Set<String> uniqueClasses = {};
      if (response != null) {
        for (var item in (response as List)) {
          String className = item['class_name']?.toString().trim() ?? '';
          if (className.isNotEmpty) {
            uniqueClasses.add(className);
          }
        }
      }

      setState(() {
        availableClasses = uniqueClasses.toList();
        availableClasses.sort();
      });
    } catch (e) {
      debugPrint("Error loading classes: $e");
    } finally {
      setState(() => isLoadingClasses = false);
    }
  }

  // Supabase থেকে পরীক্ষার নামগুলোর তালিকা লোড করা (যেমন: 1st Term, Annual ইত্যাদি)
  Future<void> _loadAcademyExams() async {
    setState(() => isLoadingExams = true);
    try {
      final response = await supabase
          .from('exam_schedules') // অথবা আপনার এক্সাম টেবিল
          .select('exam_title')
          .eq('academy_id', widget.academyId);

      Set<String> uniqueExams = {};
      if (response != null) {
        for (var item in (response as List)) {
          String examTitle = item['exam_title']?.toString().trim() ?? '';
          if (examTitle.isNotEmpty) {
            uniqueExams.add(examTitle);
          }
        }
      }

      setState(() {
        availableExams = uniqueExams.toList();
        availableExams.sort();
      });
    } catch (e) {
      debugPrint("Error loading exams: $e");
    } finally {
      setState(() => isLoadingExams = false);
    }
  }

  // নির্দিষ্ট ক্লাস সিলেক্ট করার পর সেই ক্লাসের আন্ডারে থাকা ছাত্রছাত্রীদের লোড করা
  Future<void> _loadStudentsForSelectedClass() async {
    if (selectedClass == null) return;

    setState(() => isLoadingStudents = true);
    try {
      // আপনার ডাটাবেজে স্টুডেন্ট টেবিলের নাম যদি আলাদা হয় (যেমন: 'students' বা 'academy_students') তবে তা বসিয়ে দেবেন
      final response = await supabase
          .from('students')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class_name', selectedClass!)
          .order('roll', ascending: true);

      setState(() {
        studentsList = List<Map<String, dynamic>>.from(response ?? []);
      });
    } catch (e) {
      debugPrint("Error loading students: $e");
      Get.snackbar(
        "ত্রুটি",
        "ছাত্রছাত্রীদের তালিকা লোড করতে সমস্যা হয়েছে।",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() => isLoadingStudents = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'ছাত্রছাত্রীদের রেজাল্ট ও তালিকা',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // উপরে ফিল্টার সেকশন (১ম ঘরে পরীক্ষার নাম, ২য় ঘরে ক্লাস)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // ১. প্রথম ঘর: পরীক্ষার নাম সিলেক্ট
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedExam,
                              isExpanded: true,
                              hint: const Text(
                                "পরীক্ষা সিলেক্ট করুন",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              items: availableExams.map((String examName) {
                                return DropdownMenuItem<String>(
                                  value: examName,
                                  child: Text(
                                    examName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  selectedExam = newValue;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ২. দ্বিতীয় ঘর: নির্দিষ্ট ক্লাস সিলেক্ট
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedClass,
                              isExpanded: true,
                              hint: const Text(
                                "ক্লাস সিলেক্ট করুন",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              items: availableClasses.map((String className) {
                                return DropdownMenuItem<String>(
                                  value: className,
                                  child: Text(
                                    className,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    selectedClass = newValue;
                                  });
                                  // ক্লাস সিলেক্ট করার সাথে সাথে ঐ ক্লাসের স্টুডেন্ট ফেচ হবে
                                  _loadStudentsForSelectedClass();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // নিচের অংশ: স্টুডেন্ট লিস্ট প্রদর্শন
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: (selectedExam == null || selectedClass == null)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.filter_list_alt,
                                  size: 56,
                                  color: Colors.indigo.shade200,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'দয়া করে ওপর থেকে প্রথমে "পরীক্ষা" এবং পরে "ক্লাস" সিলেক্ট করুন',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'পরীক্ষা: $selectedExam | ক্লাস: $selectedClass',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade900,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'মোট শিক্ষার্থী: ${studentsList.length} জন',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigo.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: isLoadingStudents
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : studentsList.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'এই ক্লাসে কোনো ছাত্রছাত্রী পাওয়া যায়নি।',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: studentsList.length,
                                        itemBuilder: (context, index) {
                                          var student = studentsList[index];
                                          String studentName =
                                              student['name'] ?? 'নামবিহীন';
                                          String studentRoll =
                                              student['roll']?.toString() ??
                                              'N/A';

                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey.shade200,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.02),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    Colors.indigo.shade50,
                                                child: Text(
                                                  studentRoll,
                                                  style: TextStyle(
                                                    color:
                                                        Colors.indigo.shade800,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              title: Text(
                                                studentName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              subtitle: Text(
                                                'রোল: $studentRoll',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              trailing: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.indigo.shade800,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                ),
                                                onPressed: () {
                                                  // এখানে চাইলে ছাত্রের রেজাল্ট ইনপুট বা মার্ক্স এডিট করার ডায়ালগ বা পেইজ যুক্ত করতে পারেন
                                                  Get.snackbar(
                                                    "রেজাল্ট এন্ট্রি",
                                                    "$studentName-এর নম্বর ইনপুট উইন্ডো শীঘ্রই যুক্ত হবে।",
                                                    snackPosition:
                                                        SnackPosition.BOTTOM,
                                                  );
                                                },
                                                child: const Text(
                                                  'নম্বর ইনপুট',
                                                  style: TextStyle(
                                                    fontSize: 11,
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
                ),
              ],
            ),
    );
  }
}
