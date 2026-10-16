import 'dart:async';
import 'dart:typed_data' as pw;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';

class ExamSeatPlanView extends StatefulWidget {
  final String academyId;

  const ExamSeatPlanView({super.key, required this.academyId});

  @override
  State<ExamSeatPlanView> createState() => _ExamSeatPlanViewState();
}

class _ExamSeatPlanViewState extends State<ExamSeatPlanView>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  String selectedClass = 'সব ক্লাস';
  bool isLoading = true;
  List<Map<String, dynamic>> allStudents = [];
  Map<String, List<Map<String, dynamic>>> groupedStudents = {};
  Map<String, int> classCounts = {};
  List<String> classList = [];

  List<String> examList = [];
  String? selectedExam;

  Map<String, dynamic>? academyInfo;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  final ScreenshotController _seatPlanScreenshotController =
      ScreenshotController();

  // ব্যাকগ্রাউন্ড প্রোগ্রেস এবং টাইমার ট্র্যাক করার জন্য ভেরিয়েবল
  bool isBulkGenerating = false;
  int bulkCurrentIndex = 0;
  int bulkTotalCount = 0;
  double bulkProgressPercent = 0.0;
  String bulkElapsedTime = "00:00";
  Timer? _bulkTimer;
  Stopwatch? _bulkStopwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAcademyAndData();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          searchQuery = _searchController.text.trim();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _bulkTimer?.cancel();
    _bulkStopwatch?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // অ্যাপ ব্যাকগ্রাউন্ডে বা ফোরগ্রাউন্ডে গেলেও টাইমার ও প্রসেস যাতে সচল থাকে
    super.didChangeAppLifecycleState(state);
  }

  int _compareClassNames(String a, String b) {
    if (a == 'সব ক্লাস') return -1;
    if (b == 'সব ক্লাস') return 1;

    List<String> customOrder = [
      'play',
      'প্লে',
      'nursery',
      'নার্সারি',
      'kg',
      'কেজি',
      'class 1',
      'class i',
      '১ম শ্রেণি',
      'প্রথম শ্রেণি',
      'one',
      'class 2',
      'class ii',
      '২য় শ্রেণি',
      'দ্বিতীয় শ্রেণি',
      'two',
      'class 3',
      'class iii',
      '৩য় শ্রেণি',
      'তৃতীয় শ্রেণি',
      'three',
      'class 4',
      'class iv',
      '৪র্থ শ্রেণি',
      'চতুর্থ শ্রেণি',
      'four',
      'class 5',
      'class v',
      '৫ম শ্রেণি',
      'পঞ্চম শ্রেণি',
      'five',
      'class 6',
      'class vi',
      '৬ষ্ঠ শ্রেণি',
      'ষষ্ঠ শ্রেণি',
      'six',
      'class 7',
      'class vii',
      '৭ম শ্রেণি',
      'সপ্তম শ্রেণি',
      'seven',
      'class 8',
      'class viii',
      '৮ম শ্রেণি',
      'অষ্টম শ্রেণি',
      'eight',
      'class 9',
      'class ix',
      '৯ম শ্রেণি',
      'নবম শ্রেণি',
      'nine',
      'class 10',
      'class x',
      '১০ম শ্রেণি',
      'দশম শ্রেণি',
      'ten',
    ];

    int indexA = customOrder.indexWhere(
      (item) => a.toLowerCase().contains(item),
    );
    int indexB = customOrder.indexWhere(
      (item) => b.toLowerCase().contains(item),
    );

    if (indexA != -1 && indexB != -1) {
      return indexA.compareTo(indexB);
    } else if (indexA != -1) {
      return -1;
    } else if (indexB != -1) {
      return 1;
    }

    return a.compareTo(b);
  }

  Future<void> _fetchAcademyAndData() async {
    try {
      final academyResponse = await supabase
          .from('academies')
          .select('*')
          .eq('id', widget.academyId)
          .maybeSingle();

      if (academyResponse != null) {
        academyInfo = academyResponse;
      }

      final examTitlesResponse = await supabase
          .from('exam_titles')
          .select('exam_title, created_at')
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      List list = examTitlesResponse as List;
      List<String> exams = [];
      for (var item in list) {
        String title = item['exam_title']?.toString().trim() ?? '';
        if (title.isNotEmpty && !exams.contains(title)) {
          exams.add(title);
        }
      }
      examList = exams;
      if (examList.isNotEmpty) {
        selectedExam = examList.first;
      }

      final response = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', widget.academyId);

      final List studentList = response as List;
      allStudents = studentList
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      groupedStudents.clear();
      Map<String, int> counts = {};
      counts['সব ক্লাস'] = allStudents.length;

      Set<String> classes = {};
      List<Map<String, dynamic>> allList = [];

      for (var student in allStudents) {
        String className =
            student['class']?.toString().trim() ??
            student['class_name']?.toString().trim() ??
            'অন্যান্য ক্লাস';

        if (className.isNotEmpty) {
          classes.add(className);
          counts[className] = (counts[className] ?? 0) + 1;
          groupedStudents.putIfAbsent(className, () => []).add(student);
        }
        allList.add(student);
      }
      groupedStudents['সব ক্লাস'] = allList;

      classList = classes.toList();
      classList.sort(_compareClassNames);
      classList.insert(0, 'সব ক্লাস');
      classCounts = counts;
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ডাটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildSeatPlanWidget(Map<String, dynamic> student) {
    return _DynamicSeatPlanContent(
      student: student,
      academyInfo: academyInfo,
      selectedExam: selectedExam,
    );
  }

  void _showSeatPlanDialog(BuildContext context, Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: _buildSeatPlanWidget(student)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text(
                    'বন্ধ করুন',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateAndShowPdf(Map<String, dynamic> student) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    try {
      String? imgUrl = student['image_url'];
      if (imgUrl != null && imgUrl.isNotEmpty) {
        try {
          await precacheImage(NetworkImage(imgUrl), context);
        } catch (_) {}
      }

      final imageBytes = await _seatPlanScreenshotController.captureFromWidget(
        Material(
          color: Colors.transparent,
          child: _buildSeatPlanWidget(student),
        ),
        pixelRatio: 3.0,
      );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Image(pw.MemoryImage(imageBytes), width: 260),
              ),
            );
          },
        ),
      );

      if (mounted) Navigator.pop(context);

      String studentName = student['name'] ?? student['full_name'] ?? 'student';
      String safeFileName = 'SeatPlan_$studentName'
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('$studentName - এক্সাম সিট প্লান'),
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: '$safeFileName.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      Get.snackbar(
        "ত্রুটি",
        "পিডিএফ তৈরি করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _generateAndShowBulkPdf() async {
    List<Map<String, dynamic>> targetStudents =
        groupedStudents[selectedClass] ?? [];

    if (searchQuery.trim().isNotEmpty) {
      String query = searchQuery.toLowerCase().trim();
      targetStudents = targetStudents.where((student) {
        String name = (student['name'] ?? student['full_name'] ?? '')
            .toLowerCase();
        String roll = (student['roll']?.toString() ?? '').toLowerCase();
        String phone = (student['phone'] ?? '').toLowerCase();
        return name.contains(query) ||
            roll.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    if (targetStudents.isEmpty) {
      Get.snackbar(
        "সতর্কতা",
        "ডাউনলোড করার জন্য কোনো শিক্ষার্থী পাওয়া যায়নি!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    if (mounted) {
      setState(() {
        isBulkGenerating = true;
        bulkCurrentIndex = 0;
        bulkTotalCount = targetStudents.length;
        bulkProgressPercent = 0.0;
        bulkElapsedTime = "00:00";
      });
    }

    _bulkStopwatch = Stopwatch()..start();
    _bulkTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_bulkStopwatch != null && mounted) {
        final elapsed = _bulkStopwatch!.elapsed;
        String minutes = elapsed.inMinutes.toString().padLeft(2, '0');
        String seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
        setState(() {
          bulkElapsedTime = "$minutes:$seconds";
        });
      }
    });

    try {
      final pdf = pw.Document();
      int total = targetStudents.length;

      for (int i = 0; i < total; i += 10) {
        if (!isBulkGenerating) break;

        if (mounted) {
          setState(() {
            bulkCurrentIndex = i + 1;
            bulkProgressPercent = (i + 1) / total;
          });
        }

        List<pw.Uint8List> pageImages = [];

        for (int j = i; j < i + 10 && j < total; j++) {
          if (!isBulkGenerating) break;
          final student = targetStudents[j];

          String? imgUrl = student['image_url'];
          if (imgUrl != null && imgUrl.isNotEmpty && mounted) {
            try {
              await precacheImage(NetworkImage(imgUrl), context);
            } catch (_) {}
          }

          final imgBytes = await _seatPlanScreenshotController
              .captureFromWidget(
                Material(
                  color: Colors.transparent,
                  child: _buildSeatPlanWidget(student),
                ),
                pixelRatio: 2.5,
              );
          pageImages.add(imgBytes);
        }

        if (!isBulkGenerating) break;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 15),
            build: (pw.Context context) {
              List<pw.Widget> rows = [];
              for (int r = 0; r < pageImages.length; r += 2) {
                List<pw.Widget> rowChildren = [];
                rowChildren.add(
                  pw.Image(pw.MemoryImage(pageImages[r]), width: 275),
                );
                if (r + 1 < pageImages.length) {
                  rowChildren.add(
                    pw.Image(pw.MemoryImage(pageImages[r + 1]), width: 275),
                  );
                } else {
                  rowChildren.add(pw.SizedBox(width: 275));
                }
                rows.add(
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rowChildren,
                  ),
                );
              }
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: rows,
              );
            },
          ),
        );
      }

      _bulkTimer?.cancel();
      _bulkStopwatch?.stop();
      if (mounted) {
        setState(() {
          isBulkGenerating = false;
        });
      }

      if (!mounted) return;

      String safeClassName = selectedClass
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');
      String safeFileName = 'SeatPlans_$safeClassName.pdf';

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('$selectedClass - সব এক্সাম সিট প্লান'),
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: safeFileName,
            ),
          ),
        ),
      );
    } catch (e) {
      _bulkTimer?.cancel();
      _bulkStopwatch?.stop();
      if (mounted) {
        setState(() {
          isBulkGenerating = false;
        });
      }
      Get.snackbar(
        "ত্রুটি",
        "বাল্ক পিডিএফ তৈরি করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> currentStudents =
        groupedStudents[selectedClass] ?? [];

    if (searchQuery.trim().isNotEmpty) {
      String query = searchQuery.toLowerCase().trim();
      currentStudents = currentStudents.where((student) {
        String name = (student['name'] ?? student['full_name'] ?? '')
            .toLowerCase();
        String roll = (student['roll']?.toString() ?? '').toLowerCase();
        String phone = (student['phone'] ?? '').toLowerCase();
        return name.contains(query) ||
            roll.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    return WillPopScope(
      onWillPop: () async {
        if (isBulkGenerating) {
          Get.snackbar(
            "ডাউনলোড চলছে",
            "দয়া করে ডাউনলোড শেষ হওয়া পর্যন্ত অপেক্ষা করুন অথবা ক্যানসেল করুন।",
            backgroundColor: const Color.fromARGB(255, 218, 218, 216),
            colorText: Colors.white,
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          // title: const Text('সিট প্লান ভিউ'),
          backgroundColor: const Color.fromARGB(255, 61, 109, 177),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // প্রোগ্রেস ও স্ট্যাটাস প্রদর্শনী
            if (isBulkGenerating)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "$bulkCurrentIndex/$bulkTotalCount (${(bulkProgressPercent * 100).toStringAsFixed(0)}%)\n$bulkElapsedTime",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                isBulkGenerating = false;
                              });
                            }
                            _bulkTimer?.cancel();
                            _bulkStopwatch?.stop();
                          },
                          child: const Icon(
                            Icons.cancel,
                            size: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: isBulkGenerating ? null : _generateAndShowBulkPdf,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 4.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: isBulkGenerating ? Colors.grey : Colors.white,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ডাউনলোড',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isBulkGenerating ? Colors.grey : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            if (examList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Center(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedExam,
                      dropdownColor: Colors.amber.shade900,
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      items: examList.map((String exam) {
                        return DropdownMenuItem<String>(
                          value: exam,
                          child: Text(
                            exam,
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (mounted) {
                          setState(() {
                            selectedExam = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: isLoading
            ? Center(
                child: CircularProgressIndicator(color: Colors.amber.shade800),
              )
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                'শিক্ষার্থীর নাম, রোল বা মোবাইল নম্বর দিয়ে খুঁজুন...',
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.amber.shade800,
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF4F6F9),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 42,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: classList.length,
                            itemBuilder: (context, index) {
                              String className = classList[index];
                              bool isSelected = (className == selectedClass);
                              int count = classCounts[className] ?? 0;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ChoiceChip(
                                  label: Text('$className ($count)'),
                                  selected: isSelected,
                                  selectedColor: Colors.amber.shade800,
                                  backgroundColor: const Color(0xFFF4F6F9),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  onSelected: (bool selected) {
                                    if (mounted) {
                                      setState(() {
                                        selectedClass = className;
                                      });
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: currentStudents.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 50,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'কোনো শিক্ষার্থী পাওয়া যায়নি!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: currentStudents.length,
                            padding: const EdgeInsets.all(12),
                            itemBuilder: (context, index) {
                              final student = currentStudents[index];
                              String studentName =
                                  student['name'] ??
                                  student['full_name'] ??
                                  'নামহীন';
                              String roll = student['roll']?.toString() ?? '';
                              String className =
                                  student['class'] ??
                                  student['class_name'] ??
                                  'প্রযোজ্য নয়';
                              String? studentImg = student['image_url'];

                              return Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.amber.shade800,
                                    foregroundColor: Colors.white,
                                    backgroundImage:
                                        (studentImg != null &&
                                            studentImg.isNotEmpty)
                                        ? NetworkImage(studentImg)
                                        : null,
                                    child:
                                        (studentImg == null ||
                                            studentImg.isEmpty)
                                        ? Text(
                                            roll.isNotEmpty
                                                ? roll
                                                : '${index + 1}',
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    studentName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'শ্রেণি: $className | রোল: ${roll.isNotEmpty ? roll : 'নেই'}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.visibility_rounded,
                                          color: Colors.amber.shade900,
                                        ),
                                        tooltip: 'সিট প্লানের প্রিভিউ দেখুন',
                                        onPressed: () => _showSeatPlanDialog(
                                          context,
                                          student,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.download_rounded,
                                          color: Color(0xFF2E7D32),
                                        ),
                                        tooltip: 'পিডিএফ ডাউনলোড করুন',
                                        onPressed: () =>
                                            _generateAndShowPdf(student),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DynamicSeatPlanContent extends StatelessWidget {
  final Map<String, dynamic> student;
  final Map<String, dynamic>? academyInfo;
  final String? selectedExam;

  const _DynamicSeatPlanContent({
    required this.student,
    required this.academyInfo,
    required this.selectedExam,
  });

  @override
  Widget build(BuildContext context) {
    String schoolName =
        academyInfo?['academy_name'] ??
        academyInfo?['name'] ??
        'মাদরাসা/স্কুলের নাম';
    String schoolSubtitle = academyInfo?['address'] ?? 'প্রতিষ্ঠানের ঠিকানা';
    String examName = selectedExam ?? 'বার্ষিক পরীক্ষা';

    String? logoUrl = academyInfo?['logo_url'];
    String? principalSigUrl = academyInfo?['principal_signature_url'];
    String? accountsSigUrl = academyInfo?['accounts_signature_url'];

    String studentName =
        student['name'] ?? student['full_name'] ?? 'নামহীন শিক্ষার্থী';
    String fatherName =
        student['father_name'] ?? student['fathers_name'] ?? 'N/A';
    String roll = student['roll']?.toString() ?? 'N/A';
    String className = student['class'] ?? student['class_name'] ?? 'N/A';
    String group = student['group'] ?? 'সাধারণ';
    String session = student['session'] ?? '২০২৫-২০২৬';

    String principalName = academyInfo?['principal_name'] ?? 'প্রধান শিক্ষক';
    String accountsName = academyInfo?['accounts_name'] ?? 'পরীক্ষা নিয়ন্ত্রক';
    String? imageUrl = student['image_url'];

    const String fallbackAssetPath = 'assets/images/institute logo.png';

    return Container(
      width: 175,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.red.shade800, width: 0.7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade900, width: 0.7),
                  image: DecorationImage(
                    image: (logoUrl != null && logoUrl.isNotEmpty)
                        ? NetworkImage(logoUrl) as ImageProvider
                        : const AssetImage(fallbackAssetPath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schoolName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 8,
                        color: Colors.blue.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      schoolSubtitle,
                      style: const TextStyle(
                        fontSize: 5.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      examName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 6.5,
                        color: Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 22,
                height: 28,
                decoration: BoxDecoration(
                  border: Border.all(width: 0.7),
                  image: (imageUrl != null && imageUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.grey.shade100,
                ),
                child: (imageUrl == null || imageUrl.isEmpty)
                    ? const Center(
                        child: Text('ছবি', style: TextStyle(fontSize: 3.5)),
                      )
                    : null,
              ),
            ],
          ),
          const Divider(thickness: 0.7, height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('নাম', studentName),
                    _buildInfoRow('পিতা', fatherName),
                    _buildInfoRow('রোল', roll),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('শ্রেণি', className),
                    _buildInfoRow('বিভাগ', group),
                    _buildInfoRow('সেশন', session),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  if (principalSigUrl != null && principalSigUrl.isNotEmpty)
                    SizedBox(
                      height: 7,
                      width: 26,
                      child: Image.network(
                        principalSigUrl,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    const Text(
                      '-----------------------------',
                      style: TextStyle(fontSize: 4),
                    ),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: Text(
                      principalName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 4.5,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  if (accountsSigUrl != null && accountsSigUrl.isNotEmpty)
                    SizedBox(
                      height: 7,
                      width: 26,
                      child: Image.network(accountsSigUrl, fit: BoxFit.contain),
                    )
                  else
                    const Text(
                      '-----------------------------',
                      style: TextStyle(fontSize: 4),
                    ),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: Text(
                      accountsName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 4.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 0.3),
            decoration: BoxDecoration(border: Border.all(width: 0.3)),
            child: const Text(
              'সতর্কবার্তা: পরীক্ষায় অসদুপায় অবলম্বন সম্পূর্ণ নিষিদ্ধ। অসাধু উপায় অবলম্বন করলে পরীক্ষা বাতিলসহ কঠোর শাস্তিমূলক ব্যবস্থা নেওয়া হবে।',
              style: TextStyle(
                fontSize: 3.8,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.05),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 5,
                color: Colors.black,
              ),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 5,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 5, color: Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
