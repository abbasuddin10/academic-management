import 'dart:convert';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Create or fully edit a model test.
///
/// Question immutability is enforced by the database snapshot trigger: once a
/// student has started, the question set cannot be changed (even if this UI is
/// bypassed). The UI additionally disables that section in edit mode.
class CreateCustomModelTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;
  final int totalSubjectQuestions;
  final String? currentUserId;
  final String? currentUserName;
  final ModelTest? existingTest;

  const CreateCustomModelTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
    required this.totalSubjectQuestions,
    this.currentUserId,
    this.currentUserName,
    this.existingTest,
  });

  @override
  State<CreateCustomModelTestView> createState() =>
      _CreateCustomModelTestViewState();
}

class _CreateCustomModelTestViewState extends State<CreateCustomModelTestView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _repository = ModelTestRepository();

  late final TextEditingController testTitleController;
  late final TextEditingController questionCountController;
  late final TextEditingController marksPerQuestionController;
  late final TextEditingController negativeMarksController;
  late final TextEditingController passPercentController;

  List<Map<String, dynamic>> availableChaptersData = [];
  String? selectedChapter;
  int selectedChapterQuestionCount = 0;
  bool isLoadingChapters = true;
  bool _hasAttempts = false;

  List<String> manuallySelectedQuestionIds = [];

  DateTime? startDate;
  TimeOfDay? startTime;
  DateTime? endDate;
  TimeOfDay? endTime;

  String _status = 'published';
  bool isSaving = false;
  bool _isProcessRunning = false;

  bool get _isEditing => widget.existingTest != null;
  bool get _canEditQuestions => !_isEditing || !_hasAttempts;

  @override
  void initState() {
    super.initState();
    final test = widget.existingTest;
    testTitleController = TextEditingController(
      text: test?.examTitle ?? '${widget.subjectName} মডেল টেস্ট',
    );
    questionCountController = TextEditingController(
      text: '${test?.questionCount ?? 0}',
    );
    marksPerQuestionController = TextEditingController(
      text: '${test?.marksPerQuestion ?? 1}',
    );
    negativeMarksController = TextEditingController(
      text: '${test?.negativeMarks ?? 0}',
    );
    passPercentController = TextEditingController(
      text: '${test?.passPercent ?? 33}',
    );

    if (test != null) {
      selectedChapter = test.chapterName.isEmpty ? null : test.chapterName;
      startDate = test.startAt;
      startTime = test.startAt == null
          ? null
          : TimeOfDay.fromDateTime(test.startAt!);
      endDate = test.endAt;
      endTime = test.endAt == null ? null : TimeOfDay.fromDateTime(test.endAt!);
      _status = test.isDraft ? 'draft' : test.status;
      _decodeSelectedIds(test.selectedQuestionIds);
    }
    _loadChapters();
    if (_isEditing) _checkAttempts();
  }

  void _decodeSelectedIds(String raw) {
    if (raw.trim().isEmpty) {
      manuallySelectedQuestionIds = <String>[];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        manuallySelectedQuestionIds = decoded
            .map((item) => item.toString())
            .toList();
      }
    } catch (_) {
      manuallySelectedQuestionIds = <String>[];
    }
  }

  Future<void> _checkAttempts() async {
    try {
      final attempts = await _repository.fetchAttempts(
        academyId: widget.academyId,
        testId: widget.existingTest!.id,
      );
      if (!mounted) return;
      setState(() => _hasAttempts = attempts.isNotEmpty);
    } catch (_) {
      // Conservative default: question editing stays disabled on failure.
      if (mounted) setState(() => _hasAttempts = true);
    }
  }

  /// Test duration is always derived from the chosen start/end window.
  int get _computedDurationMinutes {
    final start = _combined(startDate, startTime);
    final end = _combined(endDate, endTime);
    if (start == null || end == null) return 0;
    final minutes = end.difference(start).inMinutes;
    return minutes > 0 ? minutes : 0;
  }

  @override
  void dispose() {
    testTitleController.dispose();
    questionCountController.dispose();
    marksPerQuestionController.dispose();
    negativeMarksController.dispose();
    passPercentController.dispose();
    super.dispose();
  }

  Future<void> _loadChapters() async {
    try {
      final response = await _supabase
          .from('academy_questions')
          .select('id, chapter_name, question_text, correct_option')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName);

      final chapterCounts = <String, int>{};
      for (final item in (response as List)) {
        final chapter = item['chapter_name']?.toString().trim();
        if (chapter != null && chapter.isNotEmpty && chapter != 'EMPTY') {
          chapterCounts[chapter] = (chapterCounts[chapter] ?? 0) + 1;
        }
      }
      final chaptersList = chapterCounts.entries
          .map((entry) => {'chapter_name': entry.key, 'count': entry.value})
          .toList();
      chaptersList.sort(
        (a, b) => a['chapter_name'].toString().compareTo(
          b['chapter_name'].toString(),
        ),
      );
      if (!mounted) return;
      setState(() {
        availableChaptersData = chaptersList;
        isLoadingChapters = false;
      });
    } catch (e) {
      debugPrint('Error loading chapters: $e');
      if (mounted) setState(() => isLoadingChapters = false);
    }
  }

  Future<void> _onChapterChanged(String? chapter) async {
    if (!_canEditQuestions) return;
    setState(() {
      selectedChapter = chapter;
      manuallySelectedQuestionIds = <String>[];
      if (chapter == null) selectedChapterQuestionCount = 0;
    });
    if (chapter == null) return;
    try {
      final response = await _supabase
          .from('academy_questions')
          .select('id')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName)
          .eq('chapter_name', chapter);
      final fetched = response as List;
      if (!mounted) return;
      setState(() {
        selectedChapterQuestionCount = fetched.length;
        manuallySelectedQuestionIds = fetched
            .map((q) => q['id'].toString())
            .toList();
        questionCountController.text = '$selectedChapterQuestionCount';
      });
    } catch (e) {
      debugPrint('Error loading chapter count: $e');
    }
  }

  Future<void> _goToQuestionSelectionPage() async {
    if (selectedChapter == null || !_canEditQuestions) return;
    final result = await Get.to(
      () => SelectQuestionsView(
        academyId: widget.academyId,
        className: widget.className,
        subjectName: widget.subjectName,
        chapterName: selectedChapter!,
        initiallySelectedIds: manuallySelectedQuestionIds,
      ),
    );
    if (result is List<String> && mounted) {
      setState(() {
        manuallySelectedQuestionIds = result;
        questionCountController.text = '${result.length}';
      });
    }
  }

  DateTime? _combined(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _checkScheduleAndSave() async {
    if (_isProcessRunning || isSaving) return;
    setState(() {
      _isProcessRunning = true;
      isSaving = true;
    });
    try {
      final title = testTitleController.text.trim();
      final qCount = int.tryParse(questionCountController.text.trim());
      final marks = double.tryParse(marksPerQuestionController.text.trim());
      final negative = double.tryParse(negativeMarksController.text.trim());
      final pass = double.tryParse(passPercentController.text.trim());

      if (title.isEmpty ||
          widget.className.trim().isEmpty ||
          widget.subjectName.trim().isEmpty) {
        _warn('দয়া করে পরীক্ষার নাম, ক্লাস ও বিষয় সঠিকভাবে দিন।');
        return;
      }
      if (qCount == null || qCount <= 0) {
        _warn('প্রশ্ন সংখ্যা ০ এর বেশি হতে হবে।');
        return;
      }
      if (marks == null || marks <= 0) {
        _warn('প্রতি প্রশ্নের নম্বর ০ এর বেশি হতে হবে।');
        return;
      }
      if (negative == null || negative < 0) {
        _warn('নেগেটিভ নম্বর ০ বা তার বেশি হতে হবে।');
        return;
      }
      if (pass == null || pass < 0 || pass > 100) {
        _warn('পাস মার্কের শতাংশ ০ থেকে ১০০ এর মধ্যে দিন।');
        return;
      }

      final startLocal = _combined(startDate, startTime);
      final endLocal = _combined(endDate, endTime);
      if (startLocal == null || endLocal == null) {
        _warn('শুরু এবং শেষের তারিখ ও সময় সিলেক্ট করুন।');
        return;
      }
      // Duration is derived from the selected window — never typed manually.
      final int duration = endLocal.difference(startLocal).inMinutes;
      if (duration <= 0) {
        _warn('শেষের সময় শুরুর সময়ের কমপক্ষে ১ মিনিট পরে হতে হবে।');
        return;
      }
      if (endLocal.isBefore(DateTime.now())) {
        _warn('অতীতের সময়ে পরীক্ষা তৈরি করা যাবে না।');
        return;
      }
      // A running test keeps its original start time when it is edited; only
      // *new* past scheduling is rejected.
      final originalStart = widget.existingTest?.startAt;
      final keepsOriginalStart =
          originalStart != null &&
          startLocal.difference(originalStart).inMinutes.abs() <= 1;
      if (!keepsOriginalStart &&
          startLocal.isBefore(
            DateTime.now().subtract(const Duration(minutes: 1)),
          )) {
        _warn('শুরুর সময় অতীত হতে পারে না।');
        return;
      }
      List<String> questionIds;
      if (selectedChapter != null) {
        if (!_canEditQuestions) {
          questionIds = manuallySelectedQuestionIds;
        } else {
          if (manuallySelectedQuestionIds.isEmpty) {
            _warn('এই অধ্যায় থেকে কমপক্ষে একটি প্রশ্ন সিলেক্ট করুন।');
            return;
          }
          if (manuallySelectedQuestionIds.length != qCount) {
            _warn(
              'সিলেক্ট করা প্রশ্ন (${manuallySelectedQuestionIds.length}) ও মোট প্রশ্ন ($qCount) সংখ্যা মিলতে হবে।',
            );
            return;
          }
          questionIds = List<String>.from(manuallySelectedQuestionIds);
        }
      } else {
        final rows = await _supabase
            .from('academy_questions')
            .select('id')
            .eq('academy_id', widget.academyId)
            .eq('class_name', widget.className)
            .eq('subject_name', widget.subjectName);
        final all = List.from(rows as List);
        if (qCount > all.length) {
          _warn('পর্যাপ্ত প্রশ্ন নেই। উপলব্ধ প্রশ্ন: ${all.length} টি');
          return;
        }
        all.shuffle();
        questionIds = all.take(qCount).map((q) => q['id'].toString()).toList();
      }

      if (questionIds.isEmpty) {
        _warn('পরীক্ষার জন্য কোনো প্রশ্ন নির্বাচন করা হয়নি।');
        return;
      }

      final conflict = await _findConflict(startLocal, endLocal);
      if (conflict != null) {
        _showConflictDialog(conflict);
        return;
      }

      if (_isEditing) {
        await _repository.updateTest(
          testId: widget.existingTest!.id,
          examTitle: title,
          chapterName: selectedChapter,
          selectedQuestionIds: _canEditQuestions
              ? jsonEncode(questionIds)
              : null,
          startAt: startLocal,
          endAt: endLocal,
          status: _status,
          durationMinutes: duration,
          marksPerQuestion: marks,
          totalMarks: marks * questionIds.length,
          negativeMarks: negative,
          passPercent: pass,
        );
      } else {
        await _repository.createTest(
          academyId: widget.academyId,
          className: widget.className,
          subjectName: widget.subjectName,
          examTitle: title,
          chapterName: selectedChapter,
          selectedQuestionIds: jsonEncode(questionIds),
          startAt: startLocal,
          endAt: endLocal,
          status: _status,
          creatorId: widget.currentUserId ?? '',
          creatorName: widget.currentUserName ?? 'Teacher',
          durationMinutes: duration,
          marksPerQuestion: marks,
          totalMarks: marks * questionIds.length,
          negativeMarks: negative,
          passPercent: pass,
        );
      }
      if (!mounted) return;
      Get.back(result: true);
      Get.snackbar(
        'সফল',
        _isEditing
            ? 'মডেল টেস্ট সফলভাবে আপডেট করা হয়েছে!'
            : 'মডেল টেস্ট সফলভাবে তৈরি করা হয়েছে!',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Error saving model test: $e');
      Get.snackbar(
        'ত্রুটি',
        ModelTestRepository.friendlyError(e),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessRunning = false;
          isSaving = false;
        });
      }
    }
  }

  void _warn(String message) {
    Get.snackbar(
      'সতর্কতা',
      message,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  Future<Map<String, dynamic>?> _findConflict(
    DateTime startLocal,
    DateTime endLocal,
  ) async {
    final rows = await _supabase
        .from('exam_schedules')
        .select()
        .eq('academy_id', widget.academyId)
        .ilike('class_name', widget.className.trim());
    final startUtc = startLocal.toUtc();
    final endUtc = endLocal.toUtc();
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_isEditing && map['id']?.toString() == widget.existingTest!.id) {
        continue;
      }
      final status = map['status']?.toString() ?? 'published';
      if (status == 'cancelled' || status == 'expired') continue;
      final dbStart = DateTime.tryParse(map['start_time']?.toString() ?? '');
      final dbEnd = DateTime.tryParse(map['end_time']?.toString() ?? '');
      if (dbStart == null || dbEnd == null) continue;
      if (startUtc.isBefore(dbEnd.toUtc()) && endUtc.isAfter(dbStart.toUtc())) {
        return map;
      }
    }
    return null;
  }

  void _showConflictDialog(Map<String, dynamic> conflict) {
    final start = DateTime.tryParse(conflict['start_time']?.toString() ?? '');
    final end = DateTime.tryParse(conflict['end_time']?.toString() ?? '');
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'মডেল টেস্ট তৈরি করা সম্ভব নয়!',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '${widget.className} শ্রেণিতে এই সময়ে ইতিমধ্যে "${conflict['exam_title'] ?? 'অন্য এক পরীক্ষা'}" নির্ধারিত রয়েছে।\n'
          '${start == null ? '' : DateFormat('dd MMM, hh:mm a').format(start.toLocal())}'
          '${end == null ? '' : ' — ${DateFormat('hh:mm a').format(end.toLocal())}'}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Get.back(),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'মডেল টেস্ট সম্পাদনা' : 'নতুন মডেল টেস্ট তৈরি করুন',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildField(testTitleController, 'মডেল টেস্টের নাম'),
            const SizedBox(height: 12),
            _buildChapterSection(),
            const SizedBox(height: 12),
            _buildField(
              questionCountController,
              'পরীক্ষায় মোট কতটি প্রশ্ন থাকবে?',
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildField(
              marksPerQuestionController,
              'প্রতি প্রশ্নের নম্বর',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            _buildDurationPreview(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    negativeMarksController,
                    'নেগেটিভ নম্বর (ঐচ্ছিক)',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildField(
                    passPercentController,
                    'পাস মার্ক (%)',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'প্রকাশের অবস্থা:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('প্রকাশিত'),
                  selected: _status == 'published',
                  onSelected: (_) => setState(() => _status = 'published'),
                ),
                ChoiceChip(
                  label: const Text('খসরা'),
                  selected: _status == 'draft',
                  onSelected: (_) => setState(() => _status = 'draft'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDateTime('পরীক্ষার শুরুর সময়:', true),
            const SizedBox(height: 16),
            _buildDateTime('পরীক্ষার শেষ সময়:', false),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: (_isProcessRunning || isSaving)
                    ? null
                    : _checkScheduleAndSave,
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isEditing ? 'সংরক্ষণ করুন' : 'মডেল টেস্ট তৈরি করুন',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.tileOf(context, Colors.indigo),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.tileOf(context, Colors.indigo)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Colors.indigo),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'ক্লাস: ${widget.className}\nবিষয়: ${widget.subjectName}\nমোট মজুদ প্রশ্ন: ${widget.totalSubjectQuestions} টি',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.tileInkOf(context, Colors.indigo),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  /// Read-only preview of the duration derived from the chosen time window.
  Widget _buildDurationPreview() {
    final minutes = _computedDurationMinutes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(
          context,
          minutes > 0 ? Colors.teal : Colors.grey,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.tileOf(
            context,
            minutes > 0 ? Colors.teal : Colors.grey,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: AppTheme.tileInkOf(
              context,
              minutes > 0 ? Colors.teal : Colors.grey,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'পরীক্ষার সময়কাল (শুরু ও শেষ সময় থেকে স্বয়ংক্রিয়)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.tileInkOf(
                      context,
                      minutes > 0 ? Colors.teal : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  minutes > 0
                      ? '$minutes মিনিট'
                      : 'শুরু ও শেষের তারিখ/সময় বাছুন',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.tileInkOf(
                      context,
                      minutes > 0 ? Colors.teal : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: AppTheme.surfaceOf(context),
    ),
  );

  Widget _buildChapterSection() {
    if (!_canEditQuestions) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.tileOf(context, Colors.orange),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'শিক্ষার্থীরা এই পরীক্ষা শুরু করায় প্রশ্ন পরিবর্তন করা যাবে না। '
          'অন্যান্য তথ্য সম্পাদনা করা যাবে।',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.tileInkOf(context, Colors.orange),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isLoadingChapters
            ? const Center(child: LinearProgressIndicator())
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderOf(context)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedChapter,
                    isExpanded: true,
                    hint: const Text(
                      'নির্দিষ্ট অধ্যায় সিলেক্ট করুন (ঐচ্ছিক)',
                      style: TextStyle(fontSize: 13),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'সকল অধ্যায় (পুরো বিষয় থেকে র্যান্ডম)',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ...availableChaptersData.map((map) {
                        final name = map['chapter_name'].toString();
                        final count = map['count'];
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text('$name (প্রশ্ন আছে: $count টি)'),
                        );
                      }),
                    ],
                    onChanged: _onChapterChanged,
                  ),
                ),
              ),
        if (selectedChapter != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'সিলেক্টেড: ${manuallySelectedQuestionIds.length} / $selectedChapterQuestionCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.indigo,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _goToQuestionSelectionPage,
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text(
                  'প্রশ্ন দেখুন',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDateTime(String label, bool isStart) {
    final date = isStart ? startDate : endDate;
    final time = isStart ? startTime : endTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      if (isStart) {
                        startDate = picked;
                      } else {
                        endDate = picked;
                      }
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  date == null
                      ? 'তারিখ বাছুন'
                      : DateFormat('yyyy-MM-dd').format(date),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time ?? TimeOfDay.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      if (isStart) {
                        startTime = picked;
                      } else {
                        endTime = picked;
                      }
                    });
                  }
                },
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(time == null ? 'সময় বাছুন' : time.format(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Chapter question picker (kept as a separate route).
class SelectQuestionsView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;
  final String chapterName;
  final List<String> initiallySelectedIds;

  const SelectQuestionsView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
    required this.chapterName,
    required this.initiallySelectedIds,
  });

  @override
  State<SelectQuestionsView> createState() => _SelectQuestionsViewState();
}

class _SelectQuestionsViewState extends State<SelectQuestionsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> questions = [];
  late Set<String> selectedIds;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    selectedIds = Set<String>.from(widget.initiallySelectedIds);
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final response = await _supabase
          .from('academy_questions')
          .select('id, question_text, correct_option')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName)
          .eq('chapter_name', widget.chapterName);
      if (!mounted) return;
      setState(() {
        questions = List<Map<String, dynamic>>.from(response as List);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching chapter questions: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: Text(
          '${widget.chapterName} - প্রশ্ন নির্বাচন',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Get.back(result: selectedIds.toList()),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : questions.isEmpty
          ? const Center(child: Text('এই অধ্যায়ে কোনো প্রশ্ন পাওয়া যায়নি।'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final q = questions[index];
                final id = q['id'].toString();
                return Card(
                  child: CheckboxListTile(
                    title: Text(
                      q['question_text']?.toString() ?? 'প্রশ্ন নেই',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'সঠিক উত্তর: ${q['correct_option'] ?? 'N/A'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                    value: selectedIds.contains(id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selectedIds.add(id);
                      } else {
                        selectedIds.remove(id);
                      }
                    }),
                  ),
                );
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: AppTheme.tileOf(context, Colors.indigo),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'মোট সিলেক্টেড: ${selectedIds.length} টি',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.tileInkOf(context, Colors.indigo),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Get.back(result: selectedIds.toList()),
              child: const Text('নিশ্চিত করুন'),
            ),
          ],
        ),
      ),
    );
  }
}
