import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/services/result_calculator.dart';
import 'package:academy_management/services/result_pdf_service.dart';
import 'package:academy_management/widgets/result_sheet.dart';
import 'package:excel/excel.dart' as excel_parser;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

/// Admin / teacher result management screen. Main UI copy is English; the
/// A4 result sheet itself uses the shared [ResultSheet] widget (Bangla+English).
class AcademyResultManagementView extends StatefulWidget {
  final String academyId;
  final String? currentUserId;
  final String? currentUserName;
  final bool isReadOnly;

  const AcademyResultManagementView({
    super.key,
    required this.academyId,
    this.currentUserId,
    this.currentUserName,
    this.isReadOnly = false,
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
  bool _isGeneratingPdf = false;
  bool _bulkCancelled = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  List<String> availableClasses = [];
  String? selectedClass;

  List<String> availableExams = [];
  String? selectedExam;

  List<Map<String, dynamic>> studentsList = [];
  List<Map<String, dynamic>> filteredStudentsList = [];

  Map<String, Map<String, dynamic>> studentResultsMap = {};
  Map<String, Map<String, dynamic>> fullMarksByRoll = {};
  List<String> routineSubjects = [];

  String statusFilter = 'all';

  Map<String, dynamic> academyInfo = {};
  Uint8List? logoBytes;
  Uint8List? signatureBytes;
  final Map<String, Uint8List?> _photoCache = {};

  int get enteredCount => studentResultsMap.values
      .where((data) => ResultCalculator.hasMarks(data))
      .length;

  @override
  void initState() {
    super.initState();
    _loadAcademyInfo();
    _loadAcademyClasses();
    _loadAcademyExams();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------
  Future<void> _loadAcademyInfo() async {
    try {
      final row = await supabase
          .from('academies')
          .select()
          .eq('id', widget.academyId)
          .maybeSingle();
      if (row == null || !mounted) return;
      setState(() => academyInfo = Map<String, dynamic>.from(row));
      final logoUrl = academyInfo['logo_url']?.toString();
      final signatureUrl = (academyInfo['principal_signature_url'] ??
              academyInfo['signature_url'])
          ?.toString();
      final results = await Future.wait([
        ResultPdfService.fetchImageBytes(logoUrl),
        ResultPdfService.fetchImageBytes(signatureUrl),
      ]);
      if (!mounted) return;
      setState(() {
        logoBytes = results[0];
        signatureBytes = results[1];
      });
    } catch (e) {
      debugPrint('Academy info load skipped: $e');
    }
  }

  Future<void> _loadAcademyClasses() async {
    setState(() => isLoadingClasses = true);
    try {
      final response = await supabase
          .from('classes')
          .select('class_name, class_order')
          .eq('academy_id', widget.academyId)
          .order('class_order', ascending: true);
      final classes = <String>[];
      for (final item in (response as List)) {
        final name = item['class_name']?.toString().trim() ?? '';
        if (name.isNotEmpty && !classes.contains(name)) classes.add(name);
      }
      if (mounted) setState(() => availableClasses = classes);
    } catch (e) {
      debugPrint('Error loading classes: $e');
    } finally {
      if (mounted) setState(() => isLoadingClasses = false);
    }
  }

  Future<void> _loadAcademyExams() async {
    setState(() => isLoadingExams = true);
    try {
      final response = await supabase
          .from('exam_titles')
          .select('exam_title, created_at')
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);
      final exams = <String>[];
      for (final item in (response as List)) {
        final title = item['exam_title']?.toString().trim() ?? '';
        if (title.isNotEmpty && !exams.contains(title)) exams.add(title);
      }
      if (mounted) setState(() => availableExams = exams);
    } catch (e) {
      debugPrint('Error loading exams: $e');
    } finally {
      if (mounted) setState(() => isLoadingExams = false);
    }
  }

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
      studentsList = List<Map<String, dynamic>>.from(response);
      if (selectedExam != null) await _loadExamResultsForClass();
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading students: $e');
      _snack('Error', 'Could not load students.', Colors.red);
    } finally {
      if (mounted) setState(() => isLoadingStudents = false);
    }
  }

  Future<void> _loadRoutineSubjects() async {
    if (selectedExam == null || selectedClass == null) {
      routineSubjects = [];
      return;
    }
    try {
      final response = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);
      final subjects = <String>{};
      for (final item in (response as List)) {
        final name = item['subject_name']?.toString().trim() ?? '';
        if (name.isNotEmpty) subjects.add(name);
      }
      if (mounted) setState(() => routineSubjects = subjects.toList()..sort());
    } catch (e) {
      debugPrint('Error loading routine subjects: $e');
    }
  }

  Future<void> _loadExamResultsForClass() async {
    if (selectedClass == null || selectedExam == null) return;
    setState(() {
      studentResultsMap.clear();
      fullMarksByRoll.clear();
    });
    await _loadRoutineSubjects();
    if (!mounted) return;

    try {
      final response = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);

      final results = <String, Map<String, dynamic>>{};
      final marks = <String, Map<String, dynamic>>{};
      for (final row in (response as List)) {
        final roll = row['roll']?.toString() ?? '';
        if (row['result_data'] is Map) {
          results[roll] = Map<String, dynamic>.from(row['result_data']);
        }
        if (row['full_marks_data'] is Map) {
          marks[roll] = Map<String, dynamic>.from(row['full_marks_data']);
        }
      }
      if (!mounted) return;
      setState(() {
        studentResultsMap = results;
        fullMarksByRoll = marks;
      });
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading exam results: $e');
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      filteredStudentsList = studentsList.where((student) {
        final name = (student['name'] ?? '').toString().toLowerCase();
        final roll = (student['roll'] ?? '').toString().toLowerCase();
        final matches =
            query.isEmpty || name.contains(query) || roll.contains(query);
        if (!matches) return false;
        if (statusFilter == 'all') return true;
        final data = studentResultsMap[student['roll']?.toString()];
        final hasMarks = data != null && ResultCalculator.hasMarks(data);
        return statusFilter == 'entered' ? hasMarks : !hasMarks;
      }).toList();
    });
  }

  void _snack(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      backgroundColor: color,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Human-friendly ETA, e.g. "45s" or "2m 10s".
  static String _formatEta(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  // ---------------------------------------------------------------------------
  // Result sheet data (shared by preview and print)
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _peers() => studentsList.map((student) {
    final roll = student['roll']?.toString() ?? '';
    return <String, dynamic>{
      'roll': roll,
      'exam_title': selectedExam ?? '',
      'class_name': selectedClass ?? '',
      'result_data': studentResultsMap[roll] ?? <String, dynamic>{},
    };
  }).toList();

  Future<Uint8List?> _photoFor(Map<String, dynamic> student) async {
    final url = (student['image_url'] ?? student['photo_url'])?.toString();
    if (url == null || url.isEmpty) return null;
    if (_photoCache.containsKey(url)) return _photoCache[url];
    final bytes = await ResultPdfService.fetchImageBytes(url);
    _photoCache[url] = bytes;
    return bytes;
  }

  Future<ResultSheetData> _sheetData({
    required Map<String, dynamic> student,
    required String examTitle,
  }) async {
    final roll = student['roll']?.toString() ?? '';
    return ResultSheetData(
      academy: academyInfo,
      student: student,
      examTitle: examTitle,
      className: (student['class'] ?? selectedClass ?? '').toString(),
      resultData: studentResultsMap[roll] ?? <String, dynamic>{},
      fullMarksData: fullMarksByRoll[roll] ?? <String, dynamic>{},
      peers: _peers(),
      logoBytes: logoBytes,
      photoBytes: await _photoFor(student),
      photoUrl: (student['image_url'] ?? student['photo_url'])?.toString(),
      signatureBytes: signatureBytes,
      generatedAt: DateTime.now().toString().split('.').first,
    );
  }

  // ---------------------------------------------------------------------------
  // Excel template + upload
  // ---------------------------------------------------------------------------
  Future<void> _downloadExcelTemplate() async {
    if (selectedExam == null || selectedClass == null) return;
    try {
      final response = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);
      final subjects = <String>[];
      for (final item in (response as List)) {
        final name = item['subject_name']?.toString().trim() ?? '';
        if (name.isNotEmpty && !subjects.contains(name)) subjects.add(name);
      }
      if (subjects.isEmpty) {
        _snack('Warning', 'No subjects found in the exam routine.', Colors.orange);
        return;
      }

      final savedResults = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);
      final resultsByRoll = <String, Map<String, dynamic>>{};
      final fullByRoll = <String, Map<String, dynamic>>{};
      for (final row in (savedResults as List)) {
        final roll = row['roll']?.toString() ?? '';
        if (row['result_data'] is Map) {
          resultsByRoll[roll] = Map<String, dynamic>.from(row['result_data']);
        }
        if (row['full_marks_data'] is Map) {
          fullByRoll[roll] = Map<String, dynamic>.from(row['full_marks_data']);
        }
      }

      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      final safeName = selectedExam!.replaceAll(RegExp(r'[\\/?*[:\]]'), '').trim();
      sheet.name = safeName.length > 31 ? safeName.substring(0, 31) : safeName;
      sheet.protect('AcademyResultSecure2026');

      sheet.getRangeByIndex(5, 1).text = 'Roll';
      sheet.getRangeByIndex(5, 1).cellStyle.locked = true;
      sheet.getRangeByIndex(5, 2).text = 'Student Name';
      sheet.getRangeByIndex(5, 2).cellStyle.locked = true;

      var column = 3;
      final firstRoll = studentsList.isNotEmpty
          ? studentsList.first['roll']?.toString() ?? ''
          : '';
      for (final subject in subjects) {
        sheet.getRangeByIndex(1, column).text = subject;
        sheet.getRangeByIndex(1, column).cellStyle.locked = true;
        final savedFull = fullByRoll[firstRoll];
        sheet.getRangeByIndex(2, column).number =
            double.tryParse(savedFull?[subject]?.toString() ?? '100') ?? 100;
        sheet.getRangeByIndex(2, column).cellStyle.locked = false;
        sheet.getRangeByIndex(5, column).text = '$subject(CQ)';
        sheet.getRangeByIndex(5, column + 1).text = '$subject(MCQ)';
        sheet.getRangeByIndex(5, column + 2).text = '$subject(Viva)';
        sheet.getRangeByIndex(5, column + 3).text = '$subject(Practical)';
        for (var c = column; c <= column + 3; c++) {
          sheet.getRangeByIndex(5, c).cellStyle.locked = true;
        }
        column += 4;
      }

      var rowIndex = 6;
      for (final student in studentsList) {
        final roll = student['roll']?.toString() ?? '';
        sheet.getRangeByIndex(rowIndex, 1).text = roll;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.locked = true;
        sheet.getRangeByIndex(rowIndex, 2).text = student['name'] ?? '';
        sheet.getRangeByIndex(rowIndex, 2).cellStyle.locked = true;
        final saved = resultsByRoll[roll];
        var col = 3;
        for (final subject in subjects) {
          for (final component in ResultCalculator.components) {
            final cell = sheet.getRangeByIndex(rowIndex, col);
            final value = saved?['${subject}_$component'];
            if (value != null) {
              cell.number = double.tryParse(value.toString()) ?? 0;
            }
            cell.cellStyle.locked = false;
            col++;
          }
        }
        rowIndex++;
      }

      final totalColumns = 2 + (subjects.length * 4);
      for (var col = 1; col <= totalColumns; col++) {
        var maxLength = (sheet.getRangeByIndex(5, col).text ?? '').length;
        for (var r = 1; r <= 2; r++) {
          final text = sheet.getRangeByIndex(r, col).text ?? '';
          if (text.length > maxLength) maxLength = text.length;
        }
        if (col == 2) {
          for (final student in studentsList) {
            final name = student['name'] ?? '';
            if (name.length > maxLength) maxLength = name.length;
          }
        }
        var width = (maxLength * 6.5) + 15;
        if (col == 1) {
          width = 50;
        } else if (width < 60) {
          width = 60;
        }
        sheet.setColumnWidthInPixels(col, width.round());
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();
      if (bytes.isEmpty) return;
      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? Directory('/tmp');
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final file = File(
        '${directory.path}/${selectedClass}_${DateTime.now().year}_Result_Template.xlsx',
      );
      await file.writeAsBytes(bytes);
      _snack('Downloaded', 'Saved to ${file.path}', Colors.green);
    } catch (e) {
      debugPrint('Excel template error: $e');
      _snack('Error', 'Could not create the Excel template.', Colors.red);
    }
  }

  Future<void> _uploadAndProcessExcel() async {
    if (selectedExam == null || selectedClass == null) {
      _snack('Warning', 'Select an exam and a class first.', Colors.orange);
      return;
    }
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (picked == null || picked.files.single.path == null) return;
      if (!mounted) return;
      final bytes = await File(picked.files.single.path!).readAsBytes();
      final excelFile = excel_parser.Excel.decodeBytes(bytes);

      final routineResponse = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);
      final subjects = <String>[];
      for (final item in (routineResponse as List)) {
        final name = item['subject_name']?.toString().trim() ?? '';
        if (name.isNotEmpty && !subjects.contains(name)) subjects.add(name);
      }
      if (subjects.isEmpty) {
        _snack('Warning', 'Add subjects to the exam routine first.', Colors.orange);
        return;
      }

      for (final table in excelFile.tables.keys) {
        final sheet = excelFile.tables[table];
        if (sheet == null) continue;
        final headerRow = sheet.rows.length > 4 ? sheet.rows[4] : null;
        final hasViva = headerRow?.any(
              (cell) =>
                  cell?.value?.toString().toLowerCase().contains('viva') ??
                  false,
            ) ??
            false;
        final columnsPerSubject = hasViva ? 4 : 3;

        final fullMarksRow = sheet.rows.length > 1 ? sheet.rows[1] : null;
        final fullMarks = <String, dynamic>{};
        var fmIndex = 2;
        for (final subject in subjects) {
          fullMarks[subject] =
              fullMarksRow != null &&
                      fullMarksRow.length > fmIndex &&
                      fullMarksRow[fmIndex] != null
                  ? double.tryParse(fullMarksRow[fmIndex]!.value.toString()) ?? 100
                  : 100;
          fmIndex += columnsPerSubject;
        }

        for (var i = 5; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || row[0] == null) continue;
          final roll = row[0]?.value?.toString().trim() ?? '';
          if (roll.isEmpty) continue;
          String cellAt(int offset) => row.length > offset && row[offset] != null
              ? row[offset]!.value.toString()
              : '0';
          final marks = <String, dynamic>{};
          var index = 2;
          for (final subject in subjects) {
            marks['${subject}_cq'] = double.tryParse(cellAt(index)) ?? 0;
            marks['${subject}_mcq'] = double.tryParse(cellAt(index + 1)) ?? 0;
            marks['${subject}_viva'] =
                hasViva ? double.tryParse(cellAt(index + 2)) ?? 0 : 0;
            marks['${subject}_practical'] =
                double.tryParse(cellAt(index + (hasViva ? 3 : 2))) ?? 0;
            index += columnsPerSubject;
          }
          await supabase.from('exam_results').upsert(
            {
              'academy_id': widget.academyId,
              'exam_title': selectedExam!,
              'class_name': selectedClass!,
              'roll': roll,
              'result_data': marks,
              'full_marks_data': fullMarks,
            },
            onConflict: 'academy_id,exam_title,class_name,roll',
          );
        }
      }
      await _loadExamResultsForClass();
      _snack('Success', 'Results and full marks uploaded.', Colors.green);
    } catch (e) {
      debugPrint('Excel upload error: $e');
      _snack('Error', 'Could not upload results: $e', Colors.red);
    }
  }

  // ---------------------------------------------------------------------------
  // Edit dialog
  // ---------------------------------------------------------------------------
  Future<void> _openEditResultDialog(Map<String, dynamic> student) async {
    if (selectedExam == null || selectedClass == null) {
      _snack('Warning', 'Select an exam and a class first.', Colors.orange);
      return;
    }
    final accent = AppTheme.tileInkOf(context, Colors.indigo);
    final muted = AppTheme.mutedOf(context);
    final roll = student['roll']?.toString() ?? '';
    final name = student['name'] ?? '';

    try {
      final response = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam!)
          .eq('class_name', selectedClass!);
      final subjects = <String>[];
      for (final item in (response as List)) {
        final subject = item['subject_name']?.toString().trim() ?? '';
        if (subject.isNotEmpty && !subjects.contains(subject)) subjects.add(subject);
      }
      if (subjects.isEmpty) {
        _snack('Warning', 'No subjects found in the exam routine.', Colors.orange);
        return;
      }

      final current = studentResultsMap[roll] ?? {};
      final controllers = <String, TextEditingController>{};
      for (final subject in subjects) {
        for (final component in ResultCalculator.components) {
          controllers['${subject}_$component'] = TextEditingController(
            text: current['${subject}_$component']?.toString() ?? '0',
          );
        }
      }

      await Get.dialog(
        AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name (Roll: $roll) - Edit Result',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Edit CQ, MCQ, Viva and Practical. Full marks stay unchanged.',
                style: TextStyle(
                  fontSize: 11,
                  color: muted,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                final subject = subjects[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final component in ResultCalculator.components) ...[
                            Expanded(
                              child: TextField(
                                controller: controllers['${subject}_$component'],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: component == 'practical'
                                      ? 'Prac'
                                      : component.toUpperCase(),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final updated = <String, dynamic>{};
                for (final subject in subjects) {
                  for (final component in ResultCalculator.components) {
                    updated['${subject}_$component'] =
                        double.tryParse(
                              controllers['${subject}_$component']!.text,
                            ) ??
                        0;
                  }
                }
                await supabase.from('exam_results').upsert(
                  {
                    'academy_id': widget.academyId,
                    'exam_title': selectedExam!,
                    'class_name': selectedClass!,
                    'roll': roll,
                    'result_data': updated,
                  },
                  onConflict: 'academy_id,exam_title,class_name,roll',
                );
                Get.back();
                await _loadExamResultsForClass();
                _snack('Success', 'Result updated.', Colors.green);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Edit result error: $e');
      _snack('Error', 'Could not open the edit dialog.', Colors.red);
    }
  }

  // ---------------------------------------------------------------------------
  // View Result → the SAME A4 sheet shown in-app, with print action
  // ---------------------------------------------------------------------------
  Future<void> _openViewResult(
    Map<String, dynamic> student,
    Map<String, dynamic>? fallbackData,
  ) async {
    if (selectedExam == null) {
      _snack('Warning', 'Select an exam first.', Colors.orange);
      return;
    }
    final roll = student['roll']?.toString() ?? '';
    if (fallbackData != null &&
        studentResultsMap[roll] == null &&
        fallbackData.isNotEmpty) {
      studentResultsMap[roll] = fallbackData;
    }
    final sheet = await _sheetData(student: student, examTitle: selectedExam!);

    if (!mounted) return;
    await Get.to(
      () => ResultPreviewPage(
        data: sheet,
        title: 'Result Sheet - ${student['name'] ?? 'Student'}',
      ),
      transition: Transition.downToUp,
      duration: const Duration(milliseconds: 300),
    );
  }

  // ---------------------------------------------------------------------------
  // Download / Print
  // ---------------------------------------------------------------------------
  Future<void> _downloadStudentPdf(Map<String, dynamic> student) async {
    if (_isGeneratingPdf) return;
    if (selectedExam == null) {
      _snack('Warning', 'Select an exam first.', Colors.orange);
      return;
    }
    if (!mounted) return;
    setState(() => _isGeneratingPdf = true);
    _snack('Please wait', 'Preparing result sheet...', AppTheme.tileInkOf(context, Colors.indigo));
    try {
      final sheet = await _sheetData(student: student, examTitle: selectedExam!);
      final image = await ResultPdfService.captureSheet(sheet);
      final pdfBytes = await ResultPdfService.buildPdf([image]);
      final safeRoll = (student['roll']?.toString() ?? 'student')
          .replaceAll(RegExp(r'[^\w-]'), '_');
      await ResultPdfService.preview(
        pdfBytes,
        filename: 'result_$safeRoll.pdf',
      );
    } catch (e) {
      debugPrint('Student PDF error: $e');
      _snack('Error', 'Could not generate the PDF.', Colors.red);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _downloadClassPdf() async {
    if (_isGeneratingPdf) return;
    if (selectedExam == null || selectedClass == null) {
      _snack('Warning', 'Select an exam and a class first.', Colors.orange);
      return;
    }
    if (filteredStudentsList.isEmpty) {
      _snack('Warning', 'There are no students to export.', Colors.orange);
      return;
    }
    if (!mounted) return;

    final students = List<Map<String, dynamic>>.from(filteredStudentsList);
    final total = students.length;
    final startedAt = DateTime.now();
    final progress = ValueNotifier<int>(0);
    _bulkCancelled = false;
    setState(() => _isGeneratingPdf = true);

    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && Get.isDialogOpen == true) {
        Get.back();
        dialogOpen = false;
      }
    }

    // Live progress: X / Y + ETA derived from elapsed time, with a Cancel
    // button that only flips a flag — the loop checks it between each student.
    Get.dialog(
      PopScope<Object?>(
        canPop: false,
        child: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, current, _) {
            final remaining = total - current;
            final elapsedMs =
                DateTime.now().difference(startedAt).inMilliseconds;
            final msPerItem = current > 0 ? elapsedMs / current : 0.0;
            final eta = Duration(
              milliseconds: (msPerItem * remaining).round(),
            );
            return AlertDialog(
              title: const Text('Preparing Result Sheets'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text('$current / $total students completed'),
                  const SizedBox(height: 6),
                  Text('Estimated time remaining: ${_formatEta(eta)}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => _bulkCancelled = true,
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final images = <Uint8List>[];
      for (var index = 0; index < students.length; index++) {
        if (_bulkCancelled) break; // stop before starting the next sheet
        final sheet = await _sheetData(
          student: students[index],
          examTitle: selectedExam!,
        );
        if (_bulkCancelled) break; // stop after async image fetch
        images.add(await ResultPdfService.captureSheet(sheet));
        progress.value = index + 1;
      }

      closeDialog();
      if (_bulkCancelled) {
        if (mounted) {
          _snack('Cancelled', 'Bulk download stopped.', Colors.orange);
        }
        return;
      }

      final pdfBytes = await ResultPdfService.buildPdf(images);
      final safeName = 'results_${selectedClass}_$selectedExam'
          .replaceAll(RegExp(r'[^\w-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      await ResultPdfService.preview(pdfBytes, filename: '$safeName.pdf');
    } catch (e) {
      debugPrint('Class PDF error: $e');
      closeDialog();
      if (mounted) _snack('Error', 'Could not generate the PDF.', Colors.red);
    } finally {
      closeDialog();
      progress.dispose();
      _bulkCancelled = false;
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------
  Widget _statusChip(String value, String label) => ChoiceChip(
    label: Text(label, style: const TextStyle(fontSize: 11)),
    selected: statusFilter == value,
    onSelected: (_) {
      statusFilter = value;
      _applyFilters();
    },
  );

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final foreground = color ?? AppTheme.tileInkOf(context, Colors.indigo);
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: foreground.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.tileInkOf(context, Colors.indigo);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        // No AppBar title — search and the bulk action live in `actions`.
        actions: [
          if (_isSearching)
            Center(
              child: Container(
                width: 230,
                height: 40,
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  cursorColor: Colors.black,
                  decoration: const InputDecoration(
                    hintText: 'Search name or roll...',
                    hintStyle: TextStyle(color: Colors.black54, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => _applyFilters(),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _isGeneratingPdf ? null : _downloadClassPdf,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text(
                'একসাথে সব ডাউনলোড করুন',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          IconButton(
            tooltip: _isSearching ? 'Close search' : 'Search students',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
              _applyFilters();
            },
          ),
        ],
      ),
      body: isLoadingClasses || isLoadingExams
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceOf(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedExam,
                                isExpanded: true,
                                hint: const Text(
                                  'Select exam',
                                  style: TextStyle(fontSize: 13),
                                ),
                                items: availableExams
                                    .map(
                                      (exam) => DropdownMenuItem<String>(
                                        value: exam,
                                        child: Text(
                                          exam,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) async {
                                  setState(() {
                                    selectedExam = value;
                                    studentResultsMap.clear();
                                    fullMarksByRoll.clear();
                                  });
                                  if (selectedClass != null) {
                                    await _loadExamResultsForClass();
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedClass,
                                isExpanded: true,
                                hint: const Text(
                                  'Select class',
                                  style: TextStyle(fontSize: 13),
                                ),
                                items: availableClasses
                                    .map(
                                      (cls) => DropdownMenuItem<String>(
                                        value: cls,
                                        child: Text(
                                          cls,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) async {
                                  if (value == null) return;
                                  setState(() => selectedClass = value);
                                  await _loadStudentsForSelectedClass();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!widget.isReadOnly &&
                          selectedExam != null &&
                          selectedClass != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                  ),
                                  onPressed: _downloadExcelTemplate,
                                  icon: const Icon(Icons.download, size: 18),
                                  label: const Text('এক্সেল টেমপ্লেট ডাউনলোড করুন'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                  ),
                                  onPressed: _uploadAndProcessExcel,
                                  icon: const Icon(Icons.upload_file, size: 18),
                                  label: const Text('রেজাল্ট আপলোড করুন'),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: (selectedExam == null || selectedClass == null)
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_list_alt, size: 56),
                                SizedBox(height: 12),
                                Text(
                                  'Select an Exam first, then a Class.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                             
                             // const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _statusChip('all', 'All (${studentsList.length})'),
                                  _statusChip('entered', 'Entered ($enteredCount)'),
                                  _statusChip(
                                    'pending',
                                    'Pending (${studentsList.length - enteredCount})',
                                  ),
                                ],
                              ),
                             // const SizedBox(height: 10),
                              if (!widget.isReadOnly && routineSubjects.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.tileOf(context, Colors.orange),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.orange,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'No subjects are configured in exam_routines for this exam and class. Add subjects to the routine first.',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!isLoadingStudents &&
                                  filteredStudentsList.isNotEmpty &&
                                  studentResultsMap.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.tileOf(context, Colors.orange),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'No results have been entered for this exam and class yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: isLoadingStudents
                                    ? const Center(child: CircularProgressIndicator())
                                    : filteredStudentsList.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No students found.',
                                              style: TextStyle(color: Colors.grey),
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: filteredStudentsList.length,
                                            itemBuilder: (context, index) =>
                                                _studentCard(filteredStudentsList[index]),
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

  Widget _studentCard(Map<String, dynamic> student) {
    final name = student['name'] ?? 'Unnamed';
    final fatherName = student['father_name'] ?? 'N/A';
    final phone = student['phone'] ?? 'N/A';
    final address = student['address'] ?? 'No address';
    final className = student['class'] ?? selectedClass ?? '';
    final roll = student['roll']?.toString() ?? 'N/A';
    final imageUrl = (student['image_url'] ?? student['photo_url'])?.toString();
    final data = studentResultsMap[roll];
    final hasResult = data != null && ResultCalculator.hasMarks(data);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.tileOf(context, Colors.indigo)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.tileOf(context, Colors.indigo),
                  child: ClipOval(
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              color: AppTheme.tileInkOf(
                                context,
                                Colors.indigo,
                              ),
                              size: 30,
                            ),
                          )
                        : Icon(
                            Icons.person,
                            color: AppTheme.tileInkOf(context, Colors.indigo),
                            size: 30,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Father: $fatherName',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.mutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isReadOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.tileOf(
                        context,
                        hasResult ? Colors.green : Colors.orange,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      hasResult ? 'Entered' : 'Pending',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Text('Class: $className', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Text('Roll: $roll', style: const TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_android, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('$phone', style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address.toString(),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _actionTile(
                  icon: Icons.visibility_outlined,
                  label: 'রেজাল্ট দেখুন',
                  onTap: () => _openViewResult(student, data),
                ),
                if (!widget.isReadOnly)
                  _actionTile(
                    icon: Icons.edit_outlined,
                    label: 'রেজাল্ট এডিট',
                    onTap: () => _openEditResultDialog(student),
                  ),
                _actionTile(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'ডাউনলোড / প্রিন্ট',
                  color: AppTheme.successOf(context),
                  onTap: () => _downloadStudentPdf(student),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// In-app A4 preview of the exact sheet used for printing.
class ResultPreviewPage extends StatefulWidget {
  final ResultSheetData data;
  final String title;

  const ResultPreviewPage({
    super.key,
    required this.data,
    required this.title,
  });

  @override
  State<ResultPreviewPage> createState() => _ResultPreviewPageState();
}

class _ResultPreviewPageState extends State<ResultPreviewPage> {
  bool _isPreparing = false;

  Future<void> _printSheet() async {
    if (_isPreparing) return;
    if (!mounted) return;
    setState(() => _isPreparing = true);
    try {
      final image = await ResultPdfService.captureSheet(widget.data);
      final bytes = await ResultPdfService.buildPdf([image]);
      final roll = widget.data.student['roll']?.toString() ?? 'student';
      await ResultPdfService.preview(
        bytes,
        filename: 'result_${roll.replaceAll(RegExp(r'[^\w-]'), '_')}.pdf',
      );
    } catch (e) {
      debugPrint('Preview print error: $e');
      Get.snackbar(
        'Error',
        'Could not open the print preview.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Print / Download / Share',
            onPressed: _isPreparing ? null : _printSheet,
            icon: _isPreparing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isPreparing ? null : _printSheet,
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Print / Download / Share'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: MediaQuery(
            // Match the PDF capture: A4 size and text scale 1 so the preview
            // and the downloaded sheet are pixel-for-pixel identical.
            data: MediaQuery.of(context).copyWith(
              size: const Size(
                ResultSheet.sheetWidth,
                ResultSheet.sheetHeight,
              ),
              textScaler: TextScaler.linear(1),
            ),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ResultSheet(data: widget.data),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
