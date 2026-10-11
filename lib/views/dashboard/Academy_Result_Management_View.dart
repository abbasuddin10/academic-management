import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_parser;

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

  // সার্চ রিলেটেড ভেরিয়েবল
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // ক্লাসের তালিকা এবং সিলেক্টেড ক্লাস
  List<String> availableClasses = [];
  String? selectedClass;

  // পরীক্ষার তালিকা এবং সিলেক্টেড পরীক্ষা
  List<String> availableExams = [];
  String? selectedExam;

  // ছাত্রছাত্রীদের তালিকা এবং ফিল্টারড তালিকা
  List<Map<String, dynamic>> studentsList = [];
  List<Map<String, dynamic>> filteredStudentsList = [];

  // ছাত্রছাত্রীদের রোল অনুযায়ী সুপাবেস থেকে আনা রেজাল্ট ম্যাপ
  Map<String, Map<String, dynamic>> studentResultsMap = {};

  @override
  void initState() {
    super.initState();
    _loadAcademyClasses();
    _loadAcademyExams();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ১. 'classes' টেবিল থেকে class_order অনুযায়ী ক্রমানুসারে ক্লাস ফেচ করা
  Future<void> _loadAcademyClasses() async {
    setState(() => isLoadingClasses = true);
    try {
      final response = await supabase
          .from('classes')
          .select('class_name, class_order')
          .eq('academy_id', widget.academyId)
          .order('class_order', ascending: true);

      List<String> orderedClasses = [];
      if (response != null) {
        for (var item in (response as List)) {
          String className = item['class_name']?.toString().trim() ?? '';
          if (className.isNotEmpty && !orderedClasses.contains(className)) {
            orderedClasses.add(className);
          }
        }
      }

      setState(() {
        availableClasses = orderedClasses;
      });
    } catch (e) {
      debugPrint("Error loading classes: $e");
    } finally {
      setState(() => isLoadingClasses = false);
    }
  }

  // ২. 'exam_titles' টেবিল থেকে লেটেস্ট পরীক্ষাগুলো সবার উপরে ফেচ করা
  Future<void> _loadAcademyExams() async {
    setState(() => isLoadingExams = true);
    try {
      final response = await supabase
          .from('exam_titles')
          .select('exam_title, created_at')
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      List<String> orderedExams = [];
      if (response != null) {
        for (var item in (response as List)) {
          String examTitle = item['exam_title']?.toString().trim() ?? '';
          if (examTitle.isNotEmpty && !orderedExams.contains(examTitle)) {
            orderedExams.add(examTitle);
          }
        }
      }

      setState(() {
        availableExams = orderedExams;
      });
    } catch (e) {
      debugPrint("Error loading exams: $e");
    } finally {
      setState(() => isLoadingExams = false);
    }
  }

  // ৩. 'students' টেবিল থেকে রোল অনুযায়ী স্টুডেন্ট ফেচ করা এবং সুপাবেস থেকে রেজাল্ট লোড করা
  Future<void> _loadStudentsForSelectedClass() async {
    if (selectedClass == null) return;

    setState(() => isLoadingStudents = true);
    try {
      final response = await supabase
          .from('students')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class', selectedClass!)
          .order('roll', ascending: true);

      studentsList = List<Map<String, dynamic>>.from(response ?? []);
      filteredStudentsList = studentsList;

      // ক্লাস ও পরীক্ষা সিলেক্ট করা থাকলে সুপাবেস থেকে ঐ ক্লাসের রেজাল্টগুলো ফেচ করা
      if (selectedExam != null) {
        await _loadExamResultsForClass();
      }
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

  // সুপাবেস থেকে নির্দিষ্ট পরীক্ষার রেজাল্ট ফেচ করার ফাংশন
  Future<void> _loadExamResultsForClass() async {
    if (selectedClass == null || selectedExam == null) return;
    try {
      final resultsResponse = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      Map<String, Map<String, dynamic>> tempMap = {};
      if (resultsResponse != null) {
        for (var res in (resultsResponse as List)) {
          String roll = res['roll']?.toString() ?? '';
          if (res['result_data'] is Map) {
            tempMap[roll] = Map<String, dynamic>.from(res['result_data']);
          }
        }
      }
      setState(() {
        studentResultsMap = tempMap;
      });
    } catch (e) {
      debugPrint("Error loading exam results: $e");
    }
  }

  // ৪. Syncfusion ব্যবহার করে ডাইনামিক এক্সেল টেমপ্লেট ডাউনলোড (পূর্বের সেভ করা ডাটা JSONB থেকে ফেচ করা সহ)
  Future<void> _downloadExcelTemplate() async {
    if (selectedExam == null || selectedClass == null) return;

    try {
      Get.snackbar(
        "অপেক্ষা করুন",
        "এক্সেল ফাইল তৈরি করা হচ্ছে...",
        backgroundColor: Colors.indigo.shade800,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );

      // সুপাবেস থেকে রুটিন অনুযায়ী সাবজেক্ট লিস্ট আনা
      final routinesResponse = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      List<String> subjects = [];
      if (routinesResponse != null) {
        for (var item in (routinesResponse as List)) {
          String sub = item['subject_name']?.toString().trim() ?? '';
          if (sub.isNotEmpty && !subjects.contains(sub)) {
            subjects.add(sub);
          }
        }
      }

      if (subjects.isEmpty) {
        Get.snackbar(
          "সতর্কতা",
          "এই ক্লাসের জন্য 'exam_routines' টেবিলে কোনো বিষয় পাওয়া যায়নি!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // পূর্বের সেভ করা রেজাল্ট ও ফুল মার্কস ফেচ করা
      final existingResultsResponse = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      Map<String, Map<String, dynamic>> savedResultsMap = {};
      Map<String, Map<String, dynamic>> savedFullMarksMap = {};
      if (existingResultsResponse != null) {
        for (var res in (existingResultsResponse as List)) {
          String roll = res['roll']?.toString() ?? '';
          if (res['result_data'] is Map) {
            savedResultsMap[roll] = Map<String, dynamic>.from(
              res['result_data'],
            );
          }
          if (res['full_marks_data'] is Map) {
            savedFullMarksMap[roll] = Map<String, dynamic>.from(
              res['full_marks_data'],
            );
          }
        }
      }

      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];

      String safeSheetName = selectedExam!
          .replaceAll(RegExp(r'[\\/?*[:\]]'), '')
          .trim();
      if (safeSheetName.length > 31) {
        safeSheetName = safeSheetName.substring(0, 31);
      }
      sheet.name = safeSheetName;

      sheet.protect('AcademyResultSecure2026');

      // রো ৫: মূল হেডার (রোল, শিক্ষার্থীর নাম, এবং সাবজেক্ট অনুযায়ী CQ, MCQ, Practical)
      sheet.getRangeByIndex(5, 1).text = 'রোল';
      sheet.getRangeByIndex(5, 1).cellStyle.locked = true;
      sheet.getRangeByIndex(5, 2).text = 'শিক্ষার্থীর নাম';
      sheet.getRangeByIndex(5, 2).cellStyle.locked = true;

      int subColIndex = 3;
      for (var sub in subjects) {
        // রো ১: সুপাবেস থেকে আসা বিষয়ের নাম (লকড থাকবে)
        sheet.getRangeByIndex(1, subColIndex).text = sub;
        sheet.getRangeByIndex(1, subColIndex).cellStyle.locked = true;

        // রো ২: ফুল মার্কস (ডিফল্ট ১০০ বা পূর্বের সেভ করা মান)
        var firstRoll = studentsList.isNotEmpty
            ? studentsList.first['roll']?.toString() ?? ''
            : '';
        var savedFM = savedFullMarksMap[firstRoll];
        sheet.getRangeByIndex(2, subColIndex).number =
            double.tryParse(savedFM?[sub]?.toString() ?? '100') ?? 100;
        sheet.getRangeByIndex(2, subColIndex).cellStyle.locked =
            false; // শিক্ষক এডিট করতে পারবেন

        // রো ৫-এ সাবজেক্টের ক্যাটাগরি হেডার
        sheet.getRangeByIndex(5, subColIndex).text = '$sub(CQ)';
        sheet.getRangeByIndex(5, subColIndex + 1).text = '$sub(MCQ)';
        sheet.getRangeByIndex(5, subColIndex + 2).text = '$sub(practical)';

        for (int c = subColIndex; c <= subColIndex + 2; c++) {
          sheet.getRangeByIndex(5, c).cellStyle.locked = true;
        }

        subColIndex += 3;
      }

      // রো ৬ থেকে ছাত্রছাত্রীদের ডেটা শুরু হবে
      int rowIndex = 6;
      for (var student in studentsList) {
        String roll = student['roll']?.toString() ?? '';
        String name = student['name'] ?? '';

        sheet.getRangeByIndex(rowIndex, 1).text = roll;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.locked = true;

        sheet.getRangeByIndex(rowIndex, 2).text = name;
        sheet.getRangeByIndex(rowIndex, 2).cellStyle.locked = true;

        var studentSavedData = savedResultsMap[roll];

        int colIdx = 3;
        for (var sub in subjects) {
          final cqCell = sheet.getRangeByIndex(rowIndex, colIdx);
          if (studentSavedData != null &&
              studentSavedData['${sub}_cq'] != null) {
            cqCell.number =
                double.tryParse(studentSavedData['${sub}_cq'].toString()) ?? 0;
          }
          cqCell.cellStyle.locked = false;

          final mcqCell = sheet.getRangeByIndex(rowIndex, colIdx + 1);
          if (studentSavedData != null &&
              studentSavedData['${sub}_mcq'] != null) {
            mcqCell.number =
                double.tryParse(studentSavedData['${sub}_mcq'].toString()) ?? 0;
          }
          mcqCell.cellStyle.locked = false;

          final practicalCell = sheet.getRangeByIndex(rowIndex, colIdx + 2);
          if (studentSavedData != null &&
              studentSavedData['${sub}_practical'] != null) {
            practicalCell.number =
                double.tryParse(
                  studentSavedData['${sub}_practical'].toString(),
                ) ??
                0;
          }
          practicalCell.cellStyle.locked = false;

          colIdx += 3;
        }

        rowIndex++;
      }

      // কলামগুলোর সাইজ বা প্রস্থ লেখার সাইজ অনুযায়ী একদম ফিট করার লজিক
      int totalColumns = 2 + (subjects.length * 3);
      for (int col = 1; col <= totalColumns; col++) {
        String headerText = sheet.getRangeByIndex(5, col).text ?? '';
        int maxLength = headerText.length;

        // সুপাবেস থেকে আসা বিষয়ের নাম বা ফুল মার্কসের ঘরের টেক্সট চেক করা
        for (int r = 1; r <= 2; r++) {
          String cellText = sheet.getRangeByIndex(r, col).text ?? '';
          if (cellText.length > maxLength) {
            maxLength = cellText.length;
          }
        }

        // শিক্ষার্থীর নামের কলামের জন্য একটু বেশি জায়গা রাখা
        if (col == 2) {
          for (var st in studentsList) {
            String stName = st['name'] ?? '';
            if (stName.length > maxLength) {
              maxLength = stName.length;
            }
          }
        }

        // লেখার দৈর্ঘ্য অনুযায়ী একদম কাছাকাছি বা ফিট রাখার লজিক
        double widthInPixels = (maxLength * 6.5) + 15;
        if (col == 1) {
          widthInPixels = 50; // রোলের কলাম সাইজ
        } else if (widthInPixels < 60) {
          widthInPixels = 60; // সর্বনিম্ন কলাম সাইজ ৬০ পিক্সেল
        }

        sheet.setColumnWidthInPixels(col, widthInPixels.round());
      }

      final List<int> fileBytes = workbook.saveAsStream();
      workbook.dispose();

      if (fileBytes.isNotEmpty) {
        final Uint8List bytes = Uint8List.fromList(fileBytes);
        String fileName =
            "${selectedClass}_${DateTime.now().year}_Result_Template.xlsx";

        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        String filePath = "${directory?.path ?? ''}/$fileName";
        File file = File(filePath);
        await file.writeAsBytes(bytes);

        Get.snackbar(
          "সফল ডাউনলোড",
          "ফাইল সেভ হয়েছে:\n$filePath",
          backgroundColor: Colors.green,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error downloading excel template: $e");
    }
  }

  // ৫. পূরণকৃত এক্সেল ফাইল আপলোড এবং JSONB ফরম্যাটে সুপাবেসে সেভ (Upsert) করার ফাংশন
  // ৫. পূরণকৃত এক্সেল ফাইল আপলোড এবং JSONB ফরম্যাটে সুপাবেসে সেভ (Upsert) করার ফাংশন
  Future<void> _uploadAndProcessExcel() async {
    if (selectedExam == null || selectedClass == null) {
      Get.snackbar(
        "সতর্কতা",
        "দয়া করে প্রথমে পরীক্ষা এবং ক্লাস সিলেক্ট করুন।",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.single.path == null) return;

      Get.snackbar(
        "অপেক্ষা করুন",
        "ফাইল প্রসেসিং ও ডেটা আপলোড হচ্ছে...",
        backgroundColor: Colors.indigo.shade800,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );

      File file = File(result.files.single.path!);
      var bytes = await file.readAsBytes();
      var excelFile = excel_parser.Excel.decodeBytes(bytes);

      final routinesResponse = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      List<String> subjects = [];
      if (routinesResponse != null) {
        for (var item in (routinesResponse as List)) {
          String sub = item['subject_name']?.toString().trim() ?? '';
          if (sub.isNotEmpty && !subjects.contains(sub)) {
            subjects.add(sub);
          }
        }
      }

      for (var table in excelFile.tables.keys) {
        var sheet = excelFile.tables[table];
        if (sheet == null) continue;

        // রো ২ (ইনডেক্স ১) থেকে প্রতিটি বিষয়ের ফুল মার্কস রিড করা
        Map<String, dynamic> fullMarksScores = {};
        var fullMarksRow = sheet.rows.length > 1 ? sheet.rows[1] : null;

        int colIdx = 2;
        for (var sub in subjects) {
          double fm =
              fullMarksRow != null &&
                  fullMarksRow.length > colIdx &&
                  fullMarksRow[colIdx] != null
              ? double.tryParse(fullMarksRow[colIdx]!.value.toString()) ?? 100
              : 100;
          fullMarksScores[sub] = fm;
          colIdx += 3;
        }

        // রো ৬ (ইনডেক্স ৫) থেকে ছাত্রছাত্রীদের নম্বর রিড করা
        for (int i = 5; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty || row[0] == null) continue;

          String roll = row[0]?.value?.toString().trim() ?? '';
          if (roll.isEmpty) continue;

          Map<String, dynamic> subjectScores = {};
          int colIndex = 2;
          for (var sub in subjects) {
            String cqVal = row.length > colIndex && row[colIndex] != null
                ? row[colIndex]!.value.toString()
                : '0';
            String mcqVal =
                row.length > colIndex + 1 && row[colIndex + 1] != null
                ? row[colIndex + 1]!.value.toString()
                : '0';
            String practicalVal =
                row.length > colIndex + 2 && row[colIndex + 2] != null
                ? row[colIndex + 2]!.value.toString()
                : '0';

            subjectScores['${sub}_cq'] = double.tryParse(cqVal) ?? 0;
            subjectScores['${sub}_mcq'] = double.tryParse(mcqVal) ?? 0;
            subjectScores['${sub}_practical'] =
                double.tryParse(practicalVal) ?? 0;

            colIndex += 3;
          }

          Map<String, dynamic> rowDataToUpsert = {
            'academy_id': widget.academyId,
            'exam_title': selectedExam!,
            'class_name': selectedClass!,
            'roll': roll,
            'result_data': subjectScores,
            'full_marks_data':
                fullMarksScores, // ফুল মার্কস ডেটা সুপাবেসে সেভ হবে
          };

          await supabase
              .from('exam_results')
              .upsert(
                rowDataToUpsert,
                onConflict: 'academy_id,exam_title,class_name,roll',
              );
        }
      }

      // আপলোড শেষে কার্ডের রেজাল্ট রিফ্রেশ করার জন্য
      await _loadExamResultsForClass();

      Get.snackbar(
        "সফল",
        "সকল শিক্ষার্থীর ফলাফল ও ফুল মার্কস সফলভাবে আপলোড ও আপডেট হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint("Error uploading/processing excel: $e");
      Get.snackbar(
        "ত্রুটি",
        "ফাইল আপলোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // সুপাবেসে একক শিক্ষার্থীর রেজাল্ট এডিট বা আপডেট করার ডায়ালগ ফাংশন
  Future<void> _openEditResultDialog(Map<String, dynamic> student) async {
    if (selectedExam == null || selectedClass == null) {
      Get.snackbar(
        "সতর্কতা",
        "দয়া করে পরীক্ষা ও ক্লাস সিলেক্ট করুন।",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    String roll = student['roll']?.toString() ?? '';
    String studentName = student['name'] ?? '';

    // ঐ ক্লাসের বিষয়গুলোর তালিকা ফেচ করা
    try {
      final routinesResponse = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      List<String> subjects = [];
      if (routinesResponse != null) {
        for (var item in (routinesResponse as List)) {
          String sub = item['subject_name']?.toString().trim() ?? '';
          if (sub.isNotEmpty && !subjects.contains(sub)) {
            subjects.add(sub);
          }
        }
      }

      if (subjects.isEmpty) {
        Get.snackbar(
          "সতর্কতা",
          "এই ক্লাসের জন্য কোনো বিষয় পাওয়া যায়নি!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      // পূর্বের সেভ করা মার্কস ম্যাপ বের করা
      Map<String, dynamic> currentData = studentResultsMap[roll] ?? {};
      Map<String, TextEditingController> controllers = {};

      for (var sub in subjects) {
        controllers['${sub}_cq'] = TextEditingController(
          text: currentData['${sub}_cq']?.toString() ?? '0',
        );
        controllers['${sub}_mcq'] = TextEditingController(
          text: currentData['${sub}_mcq']?.toString() ?? '0',
        );
        controllers['${sub}_viva'] = TextEditingController(
          text: currentData['${sub}_viva']?.toString() ?? '0',
        );
        controllers['${sub}_practical'] = TextEditingController(
          text: currentData['${sub}_practical']?.toString() ?? '0',
        );
      }

      // ডায়ালগ পপআপ দেখানো
      await Get.dialog(
        AlertDialog(
          title: Text(
            '$studentName (রোল: $roll) - ফলাফল এডিট',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                String sub = subjects[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controllers['${sub}_cq'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'CQ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controllers['${sub}_mcq'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'MCQ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controllers['${sub}_viva'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Viva',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controllers['${sub}_practical'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Practical',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('বাতিল', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Map<String, dynamic> updatedScores = {};
                for (var sub in subjects) {
                  updatedScores['${sub}_cq'] =
                      double.tryParse(controllers['${sub}_cq']!.text) ?? 0;
                  updatedScores['${sub}_mcq'] =
                      double.tryParse(controllers['${sub}_mcq']!.text) ?? 0;
                  updatedScores['${sub}_viva'] =
                      double.tryParse(controllers['${sub}_viva']!.text) ?? 0;
                  updatedScores['${sub}_practical'] =
                      double.tryParse(controllers['${sub}_practical']!.text) ??
                      0;
                }

                // সুপাবেসে আপডেট (Upsert) করা
                await supabase.from('exam_results').upsert({
                  'academy_id': widget.academyId,
                  'exam_title': selectedExam!,
                  'class_name': selectedClass!,
                  'roll': roll,
                  'result_data': updatedScores,
                }, onConflict: 'academy_id,exam_title,class_name,roll');

                Get.back();
                await _loadExamResultsForClass();

                Get.snackbar(
                  "সফল",
                  "ফলাফল সফলভাবে আপডেট করা হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                );
              },
              child: const Text('সেভ করুন'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint("Error opening edit dialog: $e");
    }
  }

  // ভিউ রেজাল্ট ডায়ালগ ফাংশন
  Future<void> _openViewResultDialog(
    Map<String, dynamic> student,
    Map<String, dynamic>? studentResult,
  ) async {
    String roll = student['roll']?.toString() ?? '';
    String studentName = student['name'] ?? '';

    Get.dialog(
      AlertDialog(
        title: Text(
          '$studentName (রোল: $roll) - ফলাফল বিবরণী',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: studentResult == null || studentResult.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'এই শিক্ষার্থীর কোনো ফলাফল পাওয়া যায়নি।',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: studentResult.entries.map((entry) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        entry.key.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('বন্ধ করুন'),
          ),
        ],
      ),
    );
  }

  // সার্চের ফিল্টার ফাংশন
  void _filterStudents(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredStudentsList = studentsList;
      });
    } else {
      setState(() {
        filteredStudentsList = studentsList.where((student) {
          String name = (student['name'] ?? '').toLowerCase();
          String roll = (student['roll']?.toString() ?? '').toLowerCase();
          String searchLower = query.toLowerCase();

          return name.contains(searchLower) || roll.contains(searchLower);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'ছাত্রছাত্রীর নাম বা রোল দিয়ে সার্চ করুন...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: _filterStudents,
              )
            : const Text(
                'ছাত্রছাত্রীদের রেজাল্ট ও বিবরণী',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  filteredStudentsList = studentsList;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: isLoadingClasses || isLoadingExams
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ফিল্টার সেকশন এবং পরীক্ষার নাম ও ক্লাস সিলেক্ট করার পর দৃশ্যমান 'ডাউনলোড' ও 'আপলোড' বাটন
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // ১. পরীক্ষার নাম
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
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
                                  onChanged: (String? newValue) async {
                                    setState(() {
                                      selectedExam = newValue;
                                    });
                                    if (selectedClass != null) {
                                      await _loadExamResultsForClass();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // ২. ক্লাস সিলেক্ট
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
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
                                  items: availableClasses.map((
                                    String className,
                                  ) {
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
                                  onChanged: (String? newValue) async {
                                    if (newValue != null) {
                                      setState(() {
                                        selectedClass = newValue;
                                        _searchController.clear();
                                        _isSearching = false;
                                      });
                                      await _loadStudentsForSelectedClass();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // যদি পরীক্ষা এবং ক্লাস উভয়ই সিলেক্ট করা হয়, তবে বক্স দুটির নিচে 'ডাউনলোড' ও 'আপলোড' বাটন ভিজিবল হবে
                      if (selectedExam != null && selectedClass != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                onPressed: _downloadExcelTemplate,
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text(
                                  'ডাউনলোড',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade800,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                onPressed: _uploadAndProcessExcel,
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text(
                                  'আপলোড',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // স্টুডেন্টদের তালিকা
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
                                      'মোট শিক্ষার্থী: ${filteredStudentsList.length} জন',
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
                                    : filteredStudentsList.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'কোনো ছাত্রছাত্রী পাওয়া যায়নি।',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filteredStudentsList.length,
                                        itemBuilder: (context, index) {
                                          var student =
                                              filteredStudentsList[index];

                                          String studentName =
                                              student['name'] ?? 'নামবিহীন';
                                          String fatherName =
                                              student['father_name'] ??
                                              'পাওয়া যায়নি';
                                          String phone =
                                              student['phone'] ?? 'নেই';
                                          String address =
                                              student['address'] ??
                                              'ঠিকানা দেওয়া হয়নি';
                                          String className =
                                              student['class'] ??
                                              selectedClass ??
                                              '';
                                          String studentRoll =
                                              student['roll']?.toString() ??
                                              'N/A';
                                          String? imageUrl =
                                              student['image_url'];

                                          // কার্ডে সুপাবেস থেকে আনা ঐ ছাত্রের রেজাল্ট ডেটা
                                          var studentResult =
                                              studentResultsMap[studentRoll];
                                          bool hasResult =
                                              studentResult != null &&
                                              studentResult.isNotEmpty;

                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            elevation: 2,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              side: BorderSide(
                                                color: Colors.indigo.shade100,
                                                width: 1,
                                              ),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                12.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 26,
                                                        backgroundColor: Colors
                                                            .indigo
                                                            .shade50,
                                                        backgroundImage:
                                                            (imageUrl != null &&
                                                                imageUrl
                                                                    .isNotEmpty)
                                                            ? NetworkImage(
                                                                imageUrl,
                                                              )
                                                            : null,
                                                        child:
                                                            (imageUrl == null ||
                                                                imageUrl
                                                                    .isEmpty)
                                                            ? Icon(
                                                                Icons.person,
                                                                color: Colors
                                                                    .indigo
                                                                    .shade800,
                                                                size: 30,
                                                              )
                                                            : null,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              studentName,
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 15,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              'পিতা: $fatherName',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: Colors
                                                                    .grey
                                                                    .shade700,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // রেজাল্ট স্ট্যাটাস ব্যাজ
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: hasResult
                                                              ? Colors
                                                                    .green
                                                                    .shade50
                                                              : Colors
                                                                    .orange
                                                                    .shade50,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const Divider(height: 16),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'ক্লাস: $className',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey
                                                              .shade800,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Text(
                                                        'রোল: $studentRoll',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors
                                                              .grey
                                                              .shade800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.phone_android,
                                                        size: 14,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        phone,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey
                                                              .shade800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .location_on_outlined,
                                                        size: 14,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          address,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey
                                                                .shade700,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),

                                                  // কার্ডের নিচে দুটি বাটন: ভিউ রেজাল্ট ও রেজাল্ট এডিট
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor:
                                                                Colors
                                                                    .indigo
                                                                    .shade800,
                                                            side: BorderSide(
                                                              color: Colors
                                                                  .indigo
                                                                  .shade800,
                                                            ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                          ),
                                                          onPressed: () {
                                                            _openViewResultDialog(
                                                              student,
                                                              studentResult,
                                                            );
                                                          },
                                                          icon: const Icon(
                                                            Icons.visibility,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                            'ভিউ রেজাল্ট',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: ElevatedButton.icon(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors
                                                                    .indigo
                                                                    .shade800,
                                                            foregroundColor:
                                                                Colors.white,
                                                            elevation: 0,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                          ),
                                                          onPressed: () {
                                                            _openEditResultDialog(
                                                              student,
                                                            );
                                                          },
                                                          icon: const Icon(
                                                            Icons.edit,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                            'রেজাল্ট এডিট',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
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
                ),
              ],
            ),
    );
  }
}
