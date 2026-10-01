import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class StudentExamRoutineView extends StatefulWidget {
  final String academyId;
  final String className;

  const StudentExamRoutineView({
    Key? key,
    required this.academyId,
    required this.className,
  }) : super(key: key);

  @override
  State<StudentExamRoutineView> createState() => _StudentExamRoutineViewState();
}

class _StudentExamRoutineViewState extends State<StudentExamRoutineView> {
  final supabase = Supabase.instance.client;
  bool isInitialLoading = true;
  List<Map<String, dynamic>> examRoutines = [];

  @override
  void initState() {
    super.initState();
    _fetchStudentExamRoutine();
  }

  // সুপাবেস থেকে ব্যাকগ্রাউন্ডে ডাটা ফেচ করা
  Future<void> _fetchStudentExamRoutine() async {
    try {
      final response = await supabase
          .from('exam_routines')
          .select()
          .eq('academy_id', widget.academyId)
          .ilike('class_name', widget.className.trim())
          .order('exam_date', ascending: true);

      if (response != null && mounted) {
        setState(() {
          examRoutines = List<Map<String, dynamic>>.from(response);
          isInitialLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isInitialLoading = false;
        });
      }
      print("Error fetching exam routine: $e");
    }
  }

  // ইংরেজি তারিখকে 'দিন-মাস-বছর' (যেমন: ২০-৯-২০২৬) ফরম্যাটে রূপান্তর করার ফাংশন
  String _formatDate(String dateStr) {
    try {
      DateTime parsedDate = DateTime.parse(dateStr);
      return DateFormat('d-M-yyyy').format(parsedDate);
    } catch (e) {
      return dateStr;
    }
  }

  // ইংরেজি তারিখ থেকে বারের নাম বাংলায় রূপান্তর করার ফাংশন
  String _getDayOfWeek(String dateStr) {
    try {
      DateTime parsedDate = DateTime.parse(dateStr);
      String dayName = DateFormat('EEEE').format(parsedDate);

      switch (dayName) {
        case 'Saturday':
          return 'শনিবার';
        case 'Sunday':
          return 'রবিবার';
        case 'Monday':
          return 'সোমবার';
        case 'Tuesday':
          return 'মঙ্গলবার';
        case 'Wednesday':
          return 'বুধবার';
        case 'Thursday':
          return 'বৃহস্পতিবার';
        case 'Friday':
          return 'শুক্রবার';
        default:
          return dayName;
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // পরীক্ষার নাম অনুযায়ী রুটিনগুলোকে গ্রুপিং করা
    Map<String, List<Map<String, dynamic>>> groupedByExam = {};
    for (var routine in examRoutines) {
      String examTitle = routine['exam_title'] ?? 'পরীক্ষা';
      if (!groupedByExam.containsKey(examTitle)) {
        groupedByExam[examTitle] = [];
      }
      groupedByExam[examTitle]!.add(routine);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'পরীক্ষার রুটিন',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isInitialLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : groupedByExam.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'এই মুহূর্তে আপনার ক্লাসের কোনো পরীক্ষার রুটিন প্রকাশ করা হয়নি।',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: groupedByExam.keys.length,
              itemBuilder: (context, index) {
                String examTitle = groupedByExam.keys.elementAt(index);
                List<Map<String, dynamic>> routines = groupedByExam[examTitle]!;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        backgroundColor: Colors.white,
                        collapsedBackgroundColor: Colors.white,
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        // পরীক্ষার নাম বড় আকারে (ব্যাকগ্রাউন্ড ছাড়া)
                        title: Text(
                          examTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        children: [
                          // টেবিল হেডার
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            color: Colors.indigo.shade50.withOpacity(0.5),
                            child: const Row(
                              children: [
                                Expanded(
                                  flex: 25,
                                  child: Text(
                                    'তারিখ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 22,
                                  child: Text(
                                    'বার',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 33,
                                  child: Text(
                                    'বিষয়',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 20,
                                  child: Text(
                                    'সময়',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // টেবিল ডেটা লিস্ট (RenderFlex এড়াতে টেক্সটগুলোতে ওভারফ্লো হ্যান্ডেল করা হয়েছে)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: routines.length,
                            separatorBuilder: (context, sepIndex) =>
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEEEEEE),
                                ),
                            itemBuilder: (context, rIndex) {
                              var routine = routines[rIndex];
                              String rawDate = routine['exam_date'] ?? '';
                              String formattedDate = _formatDate(rawDate);
                              String day = _getDayOfWeek(rawDate);
                              String subject = routine['subject_name'] ?? '';
                              String time = routine['exam_time'] ?? '';

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    // তারিখ
                                    Expanded(
                                      flex: 25,
                                      child: Text(
                                        formattedDate,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // বার
                                    Expanded(
                                      flex: 22,
                                      child: Text(
                                        day,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.indigo.shade700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // বিষয় (বড় নাম হলে ট্রাংকেট বা এলিপসিস হবে যাতে ওভারফ্লো না ঘটে)
                                    Expanded(
                                      flex: 33,
                                      child: Text(
                                        subject,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    // সময় (বারের রঙের সাথে মিল রেখে)
                                    Expanded(
                                      flex: 20,
                                      child: Text(
                                        time,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.indigo.shade700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
