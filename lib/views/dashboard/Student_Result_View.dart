import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentResultView extends StatefulWidget {
  final String academyId;
  final String className;
  final String studentRoll;
  final String studentName;

  const StudentResultView({
    super.key,
    required this.academyId,
    required this.className,
    required this.studentRoll,
    required this.studentName,
  });

  @override
  State<StudentResultView> createState() => _StudentResultViewState();
}

class _StudentResultViewState extends State<StudentResultView> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> myExamResultsList = [];
  Map<String, List<Map<String, dynamic>>> classAllExamResultsMap = {};

  // কোন পরীক্ষার টেবিল হাইড থাকবে সেটি ট্র্যাক করার জন্য সেট
  final Set<String> hiddenExamTitles = {};

  @override
  void initState() {
    super.initState();
    _fetchStudentAndClassResults();
  }

  // সুপাবেস থেকে একই শ্রেণির সকল ছাত্রছাত্রীর রেজাল্ট ফেচ করে সাবজেক্ট পজিশন হিসাব করা
  Future<void> _fetchStudentAndClassResults() async {
    try {
      String cleanAcademyId = widget.academyId.trim();
      String cleanClass = widget.className.trim();
      String cleanRoll = widget.studentRoll.toString().trim();

      // ১. প্রথমে সরাসরি exam_results টেবিল থেকে সব ডেটা ফেচ করা (যাতে ফিল্টারিং মিসিং না হয়)
      final response = await supabase.from('exam_results').select();

      List<Map<String, dynamic>> allClassResults =
          List<Map<String, dynamic>>.from(response);

      // ২. যদি academyId থাকে তবে তা দিয়ে ফিল্টার করা, না থাকলে বাইপাস করা
      if (cleanAcademyId.isNotEmpty) {
        allClassResults = allClassResults.where((r) {
          String dbAcademyId = r['academy_id']?.toString().trim() ?? '';
          return dbAcademyId == cleanAcademyId;
        }).toList();
      }

      // ৩. ক্লাসের নাম দিয়ে ফিল্টার করা (বাংলা বানানের ছোটখাটো পার্থক্য এড়াতে কন্টেইন চেক)
      if (cleanClass.isNotEmpty) {
        List<Map<String, dynamic>> classFiltered = allClassResults.where((r) {
          String dbClass =
              r['class_name']?.toString().trim().toLowerCase() ?? '';
          String targetClass = cleanClass.toLowerCase();
          return dbClass.contains(targetClass) || targetClass.contains(dbClass);
        }).toList();

        // যদি ক্লাস ফিল্টারে ডেটা পাওয়া যায় তবে সেটাই ব্যবহার করা হবে, নতুবা সব ডেটা রাখা হবে
        if (classFiltered.isNotEmpty) {
          allClassResults = classFiltered;
        }
      }

      // পরীক্ষা অনুযায়ী সকল ছাত্রের রেজাল্ট গ্রুপ করা
      Map<String, List<Map<String, dynamic>>> groupedByExam = {};
      for (var row in allClassResults) {
        String examTitle = row['exam_title']?.toString() ?? '';
        groupedByExam.putIfAbsent(examTitle, () => []).add(row);
      }

      // ৪. সুনির্দিষ্ট শিক্ষার্থীর রোল দিয়ে তার নিজের রেজাল্ট ফিল্টার করা
      List<Map<String, dynamic>> myResults = allClassResults.where((r) {
        String dbRoll = r['roll']?.toString().trim() ?? '';
        return dbRoll == cleanRoll;
      }).toList();

      if (mounted) {
        setState(() {
          myExamResultsList = myResults;
          classAllExamResultsMap = groupedByExam;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching results: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // সাবজেক্টের নামসমূহ আলাদা করার জন্য হেল্পার ফাংশন[cite: 9]
  Set<String> _extractSubjects(Map<String, dynamic> resultData) {
    Set<String> subjects = {};
    for (String key in resultData.keys) {
      if (key.endsWith('_cq') ||
          key.endsWith('_mcq') ||
          key.endsWith('_practical')) {
        String sub = key.substring(0, key.lastIndexOf('_'));
        subjects.add(sub);
      }
    }
    return subjects;
  }

  // ওই নির্দিষ্ট বিষয়ের ওপর শ্রেণিতে শিক্ষার্থীর পজিশন/মেধা ক্রম হিসাব করার ফাংশন[cite: 9]
  String _calculateSubjectPosition(
    String examTitle,
    String subject,
    double myTotalMark,
  ) {
    List<Map<String, dynamic>> examClassResults =
        classAllExamResultsMap[examTitle] ?? [];

    List<double> allSubjectTotals = [];

    for (var res in examClassResults) {
      if (res['result_data'] is Map) {
        Map<String, dynamic> rData = Map<String, dynamic>.from(
          res['result_data'],
        );
        double cq =
            double.tryParse(rData['${subject}_cq']?.toString() ?? '0') ?? 0;
        double mcq =
            double.tryParse(rData['${subject}_mcq']?.toString() ?? '0') ?? 0;
        double practical =
            double.tryParse(rData['${subject}_practical']?.toString() ?? '0') ??
            0;

        double total = cq + mcq + practical;
        if (total > 0) {
          allSubjectTotals.add(total);
        }
      }
    }

    if (myTotalMark <= 0 || allSubjectTotals.isEmpty) {
      return '-';
    }

    // নম্বর বড় থেকে ছোট অনুযায়ী সর্ট করা[cite: 9]
    allSubjectTotals.sort((a, b) => b.compareTo(a));

    int rank = 1;
    for (double mark in allSubjectTotals) {
      if (myTotalMark < mark) {
        rank++;
      } else {
        break;
      }
    }

    // ইংরেজি পজিশন সাফিক্স (যেমন: 1st, 2nd, 3rd)[cite: 9]
    if (rank == 1) return '1st';
    if (rank == 2) return '2nd';
    if (rank == 3) return '3rd';
    return '${rank}th';
  }

  // সুপাবেসের ডেটা থেকে নির্দিষ্ট পরীক্ষায় উক্ত শিক্ষার্থীর ক্লাসের মধ্যে সার্বিক মেরিট পজিশন হিসাব করা
  String _calculateExamMeritPosition(String examTitle) {
    List<Map<String, dynamic>> examClassResults =
        classAllExamResultsMap[examTitle] ?? [];

    if (examClassResults.isEmpty) return '-';

    Map<String, double> studentTotalMarksMap = {};

    for (var res in examClassResults) {
      String roll = res['roll']?.toString().trim() ?? '';
      if (roll.isEmpty) continue;

      if (res['result_data'] is Map) {
        Map<String, dynamic> rData = Map<String, dynamic>.from(
          res['result_data'],
        );
        Set<String> subs = _extractSubjects(rData);
        double totalObtained = 0;

        for (var sub in subs) {
          double cq =
              double.tryParse(rData['${sub}_cq']?.toString() ?? '0') ?? 0;
          double mcq =
              double.tryParse(rData['${sub}_mcq']?.toString() ?? '0') ?? 0;
          double practical =
              double.tryParse(rData['${sub}_practical']?.toString() ?? '0') ??
              0;
          totalObtained += (cq + mcq + practical);
        }

        studentTotalMarksMap[roll] = totalObtained;
      }
    }

    if (!studentTotalMarksMap.containsKey(widget.studentRoll.trim())) {
      return '-';
    }

    double myScore = studentTotalMarksMap[widget.studentRoll.trim()]!;

    // সকল ছাত্রছাত্রীর মোট নম্বরগুলো লিস্টে নিয়ে সর্ট করা
    List<double> allScores = studentTotalMarksMap.values.toList();
    allScores.sort((a, b) => b.compareTo(a));

    int rank = 1;
    for (double score in allScores) {
      if (myScore < score) {
        rank++;
      } else {
        break;
      }
    }

    if (rank == 1) return '1st';
    if (rank == 2) return '2nd';
    if (rank == 3) return '3rd';
    return '${rank}th';
  }

  // পরীক্ষার প্রাপ্ত নম্বর ও full_marks_data থেকে পার্সেন্টেজ হিসাব করার ফাংশন
  Map<String, dynamic> _calculateExamPercentage(
    Map<String, dynamic> examResult,
  ) {
    Map<String, dynamic> resultData = {};
    Map<String, dynamic> fullMarksData = {};

    if (examResult['result_data'] is Map) {
      resultData = Map<String, dynamic>.from(examResult['result_data']);
    }
    if (examResult['full_marks_data'] is Map) {
      fullMarksData = Map<String, dynamic>.from(examResult['full_marks_data']);
    }

    Set<String> subjects = _extractSubjects(resultData);
    double totalObtained = 0;
    double totalFullMarks = 0;

    for (var sub in subjects) {
      double cq =
          double.tryParse(resultData['${sub}_cq']?.toString() ?? '0') ?? 0;
      double mcq =
          double.tryParse(resultData['${sub}_mcq']?.toString() ?? '0') ?? 0;
      double practical =
          double.tryParse(resultData['${sub}_practical']?.toString() ?? '0') ??
          0;

      double subTotalObtained = cq + mcq + practical;
      totalObtained += subTotalObtained;

      double subFullMark =
          double.tryParse(fullMarksData[sub]?.toString() ?? '100') ?? 100;
      totalFullMarks += subFullMark;
    }

    if (totalFullMarks <= 0) {
      return {'progressValue': 0.0, 'percentageStr': '0%'};
    }

    double percentage = (totalObtained / totalFullMarks);
    if (percentage > 1.0) percentage = 1.0;

    String percentageStr = '${(percentage * 100).toStringAsFixed(0)}%';
    return {'progressValue': percentage, 'percentageStr': percentageStr};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('পরীক্ষার ফলাফল'),
        backgroundColor: const Color(0xFF1B365D), // গাঢ় নীল থিম[cite: 9]
        foregroundColor: Colors.white,
      ),
      // নিচে AI Assist ফ্লোটিং বাটন[cite: 9]
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // পরবর্তীতে জেমিনি চ্যাট বা প্ল্যানিং লজিক এখানে যুক্ত করা হবে[cite: 9]
        },
        backgroundColor: const Color(0xFF1B365D),
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text('AI Assist', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : myExamResultsList.isEmpty
          ? const Center(
              child: Text(
                'এই মুহূর্তে আপনার কোনো পরীক্ষার ফলাফল পাওয়া যায়নি।',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ডিজাইনের একেবারে উপরে ডাইনামিক প্রগ্রেস ওভারভিউ কার্ড
                if (myExamResultsList.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'একাডেমিক প্রগ্রেস ওভারভিউ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B365D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: myExamResultsList.map((examRes) {
                              String title = examRes['exam_title'] ?? 'পরীক্ষা';
                              Map<String, dynamic> calc =
                                  _calculateExamPercentage(examRes);
                              double progressValue = calc['progressValue'];
                              String percentageStr = calc['percentageStr'];

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                ),
                                child: _buildProgressIndicator(
                                  title,
                                  progressValue,
                                  percentageStr,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                // মূল পরীক্ষার রেজাল্ট টেবিল লিস্ট[cite: 9]
                ...myExamResultsList.asMap().entries.map((mapEntry) {
                  final examResult = mapEntry.value;
                  String examTitle = examResult['exam_title'] ?? 'পরীক্ষা';
                  Map<String, dynamic> resultData = {};

                  if (examResult['result_data'] is Map) {
                    resultData = Map<String, dynamic>.from(
                      examResult['result_data'],
                    );
                  }

                  Set<String> subjects = _extractSubjects(resultData);
                  bool isHidden = hiddenExamTitles.contains(examTitle);

                  // নির্দিষ্ট পরীক্ষার মেরিট পজিশন হিসাব করা
                  String meritPosition = _calculateExamMeritPosition(examTitle);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // পরীক্ষার শিরোনাম এবং তার সামনে মেরিট পজিশন এবং টেবিল হাইড/শো বাটন
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isHidden) {
                                hiddenExamTitles.remove(examTitle);
                              } else {
                                hiddenExamTitles.add(examTitle);
                              }
                            });
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      examTitle,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1B365D),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.indigo.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        'মেরিট: $meritPosition',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1B365D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  isHidden
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                  color: const Color(0xFF1B365D),
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (isHidden) {
                                      hiddenExamTitles.remove(examTitle);
                                    } else {
                                      hiddenExamTitles.add(examTitle);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // যদি হাইড করা না থাকে তবেই টেবিলটি দৃশ্যমান হবে[cite: 9]
                        if (!isHidden) ...[
                          subjects.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    'নম্বর এন্ট্রি করা হয়নি',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : Table(
                                  border: TableBorder.all(
                                    color: Colors.blueGrey.shade300,
                                    width: 1,
                                  ),
                                  columnWidths: const {
                                    0: FlexColumnWidth(2.5), // বিষয়[cite: 9]
                                    1: FlexColumnWidth(1.0), // CQ[cite: 9]
                                    2: FlexColumnWidth(1.0), // MCQ[cite: 9]
                                    3: FlexColumnWidth(
                                      1.2,
                                    ), // Practical[cite: 9]
                                    4: FlexColumnWidth(1.2), // Total[cite: 9]
                                    5: FlexColumnWidth(
                                      1.0,
                                    ), // Position[cite: 9]
                                  },
                                  children: [
                                    // গাঢ় নীল কালারের হেডার রো[cite: 9]
                                    TableRow(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1B365D),
                                      ),
                                      children: const [
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            'বিষয়',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'CQ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'MCQ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'Prac',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'Total',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'Pos',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // হালকা নীল ও সাদা কালারের অল্টারনেটিভ ডাটা রো[cite: 9]
                                    ...subjects.toList().asMap().entries.map((
                                      entry,
                                    ) {
                                      String sub = entry.value;
                                      bool isEven = entry.key % 2 == 0;

                                      double cq =
                                          double.tryParse(
                                            resultData['${sub}_cq']
                                                    ?.toString() ??
                                                '0',
                                          ) ??
                                          0;
                                      double mcq =
                                          double.tryParse(
                                            resultData['${sub}_mcq']
                                                    ?.toString() ??
                                                '0',
                                          ) ??
                                          0;
                                      double practical =
                                          double.tryParse(
                                            resultData['${sub}_practical']
                                                    ?.toString() ??
                                                '0',
                                          ) ??
                                          0;

                                      double total = cq + mcq + practical;

                                      // শ্রেণিভিত্তিক পজিশন হিসাব[cite: 9]
                                      String position =
                                          _calculateSubjectPosition(
                                            examTitle,
                                            sub,
                                            total,
                                          );

                                      return TableRow(
                                        decoration: BoxDecoration(
                                          color: isEven
                                              ? Colors.blue.shade50.withOpacity(
                                                  0.5,
                                                )
                                              : Colors.white,
                                        ),
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              sub.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '$cq',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '$mcq',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '$practical',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '$total',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.black87,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              position,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  // প্রগ্রেস ইন্ডিকেটর উইজেট তৈরির হেল্পার মেথড (সার্কেলের মধ্যে পার্সেন্টেজ দেখানোর জন্য আপডেট করা)
  Widget _buildProgressIndicator(
    String title,
    double value,
    String percentage,
  ) {
    return Container(
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: value,
                  backgroundColor: Colors.blue.shade100,
                  color: const Color(0xFF1B365D),
                  strokeWidth: 4.5,
                ),
                Center(
                  child: Text(
                    percentage,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B365D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
