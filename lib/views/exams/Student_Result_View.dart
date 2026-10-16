import 'package:academy_management/services/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final Set<String> hiddenExamTitles = {};

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetchStudentAndClassResults();

    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _fetchStudentAndClassResults() async {
    try {
      String cleanAcademyId = widget.academyId.trim();
      String cleanRoll = widget.studentRoll.toString().trim();
      int? rollInt = int.tryParse(cleanRoll);

      // যদি widget থেকে academyId ফাঁকা আসে, SharedPreferences থেকে নেওয়া
      if (cleanAcademyId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        cleanAcademyId = prefs.getString('student_academy_id') ?? '';
      }

      debugPrint(
        "Final Fetch -> Academy ID: '$cleanAcademyId', Roll: '$cleanRoll'",
      );

      if (cleanAcademyId.isEmpty) {
        debugPrint("Error: Academy ID is completely empty!");
        setState(() => isLoading = false);
        return;
      }

      // 🔥 শুধুমাত্র academy_id দিয়ে সুপাবেস থেকে ডাটা এনে কোডের ভেতরে রোল মেলানো (যাতে ক্লাস নেম বা টাইপ মিসম্যাচের সমস্যা না হয়)
      final response = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', cleanAcademyId);

      List<Map<String, dynamic>> allAcademyResults =
          List<Map<String, dynamic>>.from(response);
      debugPrint(
        "Total rows fetched from Supabase: ${allAcademyResults.length}",
      );

      List<Map<String, dynamic>> myResults = [];
      for (var row in allAcademyResults) {
        String dbRoll = row['roll']?.toString().trim() ?? '';
        int? dbRollInt = int.tryParse(dbRoll);

        if (dbRoll == cleanRoll ||
            dbRoll == cleanRoll.replaceAll(RegExp(r'^0+'), '') ||
            (rollInt != null && dbRollInt != null && rollInt == dbRollInt)) {
          myResults.add(row);
        }
      }

      debugPrint("Matched personal results count: ${myResults.length}");

      Map<String, List<Map<String, dynamic>>> groupedByExam = {};
      for (var row in allAcademyResults) {
        String examTitle = row['exam_title']?.toString().trim() ?? '';
        if (examTitle.isNotEmpty) {
          groupedByExam.putIfAbsent(examTitle, () => []).add(row);
        }
      }

      if (mounted) {
        setState(() {
          myExamResultsList = myResults;
          classAllExamResultsMap = groupedByExam;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching student results: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

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

    allSubjectTotals.sort((a, b) => b.compareTo(a));

    int rank = 1;
    for (double mark in allSubjectTotals) {
      if (myTotalMark < mark) {
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
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
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
                  String meritPosition = _calculateExamMeritPosition(examTitle);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                    0: FlexColumnWidth(2.5),
                                    1: FlexColumnWidth(1.0),
                                    2: FlexColumnWidth(1.0),
                                    3: FlexColumnWidth(1.2),
                                    4: FlexColumnWidth(1.2),
                                    5: FlexColumnWidth(1.0),
                                  },
                                  children: [
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
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : const SizedBox.shrink(),
    );
  }

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
