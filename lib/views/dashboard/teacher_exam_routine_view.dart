import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TeacherExamRoutineView extends StatefulWidget {
  final String academyId;

  const TeacherExamRoutineView({Key? key, required this.academyId})
    : super(key: key);

  @override
  State<TeacherExamRoutineView> createState() => _TeacherExamRoutineViewState();
}

class _TeacherExamRoutineViewState extends State<TeacherExamRoutineView> {
  final supabase = Supabase.instance.client;
  bool isInitialLoading = true;
  List<Map<String, dynamic>> examRoutines = [];

  List<String> examTitles = [];
  String? selectedExamTitle;

  @override
  void initState() {
    super.initState();
    _fetchExamTitlesAndRoutine();
  }

  Future<void> _fetchExamTitlesAndRoutine() async {
    try {
      final titleResponse = await supabase
          .from('exam_titles')
          .select('exam_title');

      if (titleResponse != null) {
        List<String> titles = [];
        for (var item in titleResponse) {
          if (item['exam_title'] != null) {
            titles.add(item['exam_title'].toString());
          }
        }
        setState(() {
          examTitles = titles.toSet().toList();
          if (examTitles.isNotEmpty) {
            selectedExamTitle = examTitles.first;
          }
        });
      }

      final response = await supabase
          .from('exam_routines')
          .select()
          .eq('academy_id', widget.academyId);

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

  String _formatDate(String dateStr) {
    try {
      DateTime parsedDate = DateTime.parse(dateStr);
      return DateFormat('d-M-yyyy').format(parsedDate);
    } catch (e) {
      return dateStr;
    }
  }

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

  // স্মার্ট এবং প্রফেশনাল পিডিএফ জেনারেশন ফাংশন
  Future<void> _generatePdf(List<Map<String, dynamic>> filteredRoutines) async {
    final pdf = pw.Document();

    // ফন্ট লোড করা
    final fontData = await rootBundle.load('assets/fonts/Ekush-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pw_pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'একাডেমি ম্যানেজমেন্ট সিস্টেম',
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 14,
                  color: pw_pdf.PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'পরীক্ষার রুটিন: ${selectedExamTitle ?? ''}',
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: pw_pdf.PdfColor.fromInt(0xFF00796B),
                ),
              ),
              pw.Divider(
                color: pw_pdf.PdfColor.fromInt(0xFF00796B),
                thickness: 1.5,
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'পৃষ্ঠা ${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(
                font: ttf,
                fontSize: 10,
                color: pw_pdf.PdfColors.grey,
              ),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.Table.fromTextArray(
              headers: [
                'তারিখ ও বার',
                'শ্রেণী',
                'পরীক্ষার শিরোনাম',
                'বিষয়',
                'সময়',
              ],
              data: filteredRoutines.map((routine) {
                String rawDate = routine['exam_date'] ?? '';
                String dateDayFormatted =
                    '${_formatDate(rawDate)}\n(${_getDayOfWeek(rawDate)})';
                return [
                  dateDayFormatted,
                  routine['class_name'] ?? '',
                  routine['exam_title'] ?? '',
                  routine['subject_name'] ?? '',
                  routine['exam_time'] ?? '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                font: ttf,
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: pw_pdf.PdfColors.white,
              ),
              cellStyle: pw.TextStyle(
                font: ttf,
                fontSize: 10,
                color: pw_pdf.PdfColors.black,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: pw_pdf.PdfColor.fromInt(0xFF00796B),
              ),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: pw_pdf.PdfColors.grey300,
                    width: 0.5,
                  ),
                ),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(2.5),
                4: const pw.FlexColumnWidth(2.0),
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (pw_pdf.PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredExamRoutines = examRoutines;
    if (selectedExamTitle != null) {
      filteredExamRoutines = examRoutines.where((routine) {
        return routine['exam_title'] == selectedExamTitle;
      }).toList();
    }

    Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var routine in filteredExamRoutines) {
      String rawDate = routine['exam_date'] ?? 'তারিখবিহীন';
      if (!groupedByDate.containsKey(rawDate)) {
        groupedByDate[rawDate] = [];
      }
      groupedByDate[rawDate]!.add(routine);
    }

    List<String> sortedDates = groupedByDate.keys.toList();
    DateTime today = DateTime.parse(
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );

    sortedDates.sort((a, b) {
      DateTime? dateA = DateTime.tryParse(a);
      DateTime? dateB = DateTime.tryParse(b);

      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      bool isPastA = dateA.isBefore(today);
      bool isPastB = dateB.isBefore(today);

      if (isPastA != isPastB) {
        return isPastA ? 1 : -1;
      }

      if (!isPastA && !isPastB) {
        return dateA.compareTo(dateB);
      } else {
        return dateB.compareTo(dateA);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: examTitles.isEmpty
            ? const Text(
                'তারিখ অনুযায়ী পরীক্ষার রুটিন',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 18,
                ),
              )
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedExamTitle,
                  dropdownColor: Colors.teal.shade700,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  items: examTitles.map((String title) {
                    return DropdownMenuItem<String>(
                      value: title,
                      child: Text(
                        title,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedExamTitle = newValue;
                    });
                  },
                ),
              ),
        backgroundColor: Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF ডাউনলোড',
            onPressed: () {
              if (filteredExamRoutines.isNotEmpty) {
                _generatePdf(filteredExamRoutines);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ডাউনলোড করার জন্য কোনো রুটিন নেই!'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: isInitialLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : sortedDates.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'এই মুহূর্তে কোনো পরীক্ষার রুটিন প্রকাশ করা হয়নি।',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: sortedDates.length,
              itemBuilder: (context, index) {
                String rawDate = sortedDates[index];
                List<Map<String, dynamic>> routines = groupedByDate[rawDate]!;

                String formattedDate = _formatDate(rawDate);
                String dayName = _getDayOfWeek(rawDate);

                bool isPastDate = false;
                DateTime? parsedRowDate = DateTime.tryParse(rawDate);
                if (parsedRowDate != null) {
                  isPastDate = parsedRowDate.isBefore(today);
                }

                int halfLength = (routines.length / 2).ceil();
                List<Map<String, dynamic>> leftRoutines = routines.sublist(
                  0,
                  halfLength,
                );
                List<Map<String, dynamic>> rightRoutines = routines.sublist(
                  halfLength,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        backgroundColor: Colors.white,
                        collapsedBackgroundColor: Colors.white,
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        title: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (isPastDate)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'সম্পন্ন',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ),
                            color: Colors.teal.shade50.withOpacity(0.5),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          'শ্রেণী',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          'বিষয় / সময়',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 1,
                                  height: 14,
                                  color: Colors.teal.shade200,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          'শ্রেণী',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          'বিষয় / সময়',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: halfLength,
                            separatorBuilder: (context, sepIndex) =>
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEEEEEE),
                                ),
                            itemBuilder: (context, rIndex) {
                              var leftItem = leftRoutines[rIndex];
                              var rightItem = (rIndex < rightRoutines.length)
                                  ? rightRoutines[rIndex]
                                  : null;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 5,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  leftItem['class_name'] ?? '',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  leftItem['exam_title'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 15),
                                          Expanded(
                                            flex: 5,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  leftItem['subject_name'] ??
                                                      '',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  leftItem['exam_time'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.teal.shade700,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 1,
                                      height: 24,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: rightItem != null
                                          ? Row(
                                              children: [
                                                Expanded(
                                                  flex: 5,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        rightItem['class_name'] ??
                                                            '',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.black87,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        rightItem['exam_title'] ??
                                                            '',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  flex: 5,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        rightItem['subject_name'] ??
                                                            '',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.teal,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        rightItem['exam_time'] ??
                                                            '',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: Colors
                                                              .teal
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const SizedBox(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 4),
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
