import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// ১. মূল পেজ: মডেল টেস্ট তৈরির ফরম
class CreateCustomModelTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;
  final int totalSubjectQuestions;
  final String? currentUserId;
  final String? currentUserName;

  const CreateCustomModelTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
    required this.totalSubjectQuestions,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<CreateCustomModelTestView> createState() =>
      _CreateCustomModelTestViewState();
}

class _CreateCustomModelTestViewState extends State<CreateCustomModelTestView> {
  final SupabaseClient supabase = Supabase.instance.client;

  late final TextEditingController testTitleController;
  final TextEditingController questionCountController = TextEditingController();

  List<Map<String, dynamic>> availableChaptersData = [];
  String? selectedChapter;
  int selectedChapterQuestionCount = 0;
  bool isLoadingChapters = true;

  // ম্যানুয়ালি সিলেক্ট করা প্রশ্নগুলোর আইডি সংরক্ষণের জন্য
  List<String> manuallySelectedQuestionIds = [];

  DateTime? startDate;
  TimeOfDay? startTime;
  DateTime? endDate;
  TimeOfDay? endTime;

  bool isSaving = false;
  bool _isProcessRunning = false; // ডাবল ক্লিক বা রেস কন্ডিশন প্রতিরোধের জন্য

  @override
  void initState() {
    super.initState();
    testTitleController = TextEditingController(
      text: '${widget.subjectName} মডেল টেস্ট',
    );
    _loadChapters();
  }

  @override
  void dispose() {
    testTitleController.dispose();
    questionCountController.dispose();
    super.dispose();
  }

  // নির্দিষ্ট একাডেমি, ক্লাস ও বিষয়ের অধ্যায় এবং প্রতি অধ্যায়ের প্রশ্ন সংখ্যা লোড করা
  Future<void> _loadChapters() async {
    try {
      final response = await supabase
          .from('academy_questions')
          .select('id, chapter_name, question_text, correct_option')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName);

      Map<String, int> chapterCounts = {};

      if (response != null) {
        for (var item in (response as List)) {
          String? chapter = item['chapter_name']?.toString().trim();
          if (chapter != null && chapter.isNotEmpty && chapter != 'EMPTY') {
            chapterCounts[chapter] = (chapterCounts[chapter] ?? 0) + 1;
          }
        }
      }

      List<Map<String, dynamic>> chaptersList = [];
      chapterCounts.forEach((chapter, count) {
        chaptersList.add({'chapter_name': chapter, 'count': count});
      });

      chaptersList.sort(
        (a, b) => a['chapter_name'].compareTo(b['chapter_name']),
      );

      setState(() {
        availableChaptersData = chaptersList;
        isLoadingChapters = false;
      });
    } catch (e) {
      debugPrint("Error loading chapters: $e");
      setState(() => isLoadingChapters = false);
    }
  }

  // অধ্যায় পরিবর্তনের সময়
  Future<void> _onChapterChanged(String? chapter) async {
    setState(() {
      selectedChapter = chapter;
      manuallySelectedQuestionIds.clear();
      if (chapter == null) {
        selectedChapterQuestionCount = 0;
      }
    });

    if (chapter != null) {
      try {
        final response = await supabase
            .from('academy_questions')
            .select('id')
            .eq('academy_id', widget.academyId)
            .eq('class_name', widget.className)
            .eq('subject_name', widget.subjectName)
            .eq('chapter_name', chapter);

        List fetchedList = response ?? [];
        setState(() {
          selectedChapterQuestionCount = fetchedList.length;
          manuallySelectedQuestionIds = fetchedList
              .map((q) => q['id'].toString())
              .toList();
          questionCountController.text = selectedChapterQuestionCount
              .toString();
        });
      } catch (e) {
        debugPrint("Error loading chapter count: $e");
      }
    }
  }

  // আলাদা পেজে প্রশ্ন সিলেক্ট করার জন্য নেভিগেট করা
  void _goToQuestionSelectionPage() async {
    if (selectedChapter == null) return;

    final result = await aliasGetToSelectQuestions();

    if (result != null && result is List<String>) {
      setState(() {
        manuallySelectedQuestionIds = result;
        questionCountController.text = manuallySelectedQuestionIds.length
            .toString();
      });
    }
  }

  Future<dynamic> aliasGetToSelectQuestions() async {
    return await Get.to(
      () => SelectQuestionsView(
        academyId: widget.academyId,
        className: widget.className,
        subjectName: widget.subjectName,
        chapterName: selectedChapter!,
        initiallySelectedIds: manuallySelectedQuestionIds,
      ),
    );
  }

  // নির্দিষ্ট ক্লাসের জন্য সিলেক্ট করা সময় ও তারিখে ইতিমধ্যে কোনো পরীক্ষা আছে কি না তা UTC টাইমজোনে নিখুঁতভাবে চেক করার ফাংশন
  Future<void> _checkScheduleAndSave() async {
    if (_isProcessRunning || isSaving) return;

    setState(() {
      _isProcessRunning = true;
      isSaving = true;
    });

    try {
      String title = testTitleController.text.trim();
      int? qCount = int.tryParse(questionCountController.text.trim());

      if (title.isEmpty || qCount == null || qCount <= 0) {
        Get.snackbar(
          "সতর্কতা",
          "দয়া করে সঠিক নাম এবং প্রশ্ন সংখ্যা দিন।",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      if (startDate == null ||
          startTime == null ||
          endDate == null ||
          endTime == null) {
        Get.snackbar(
          "সতর্কতা",
          "দয়া করে শুরু এবং শেষের তারিখ ও সময় সিলেক্ট করুন।",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      // ইউজার যে লোকাল টাইম সিলেক্ট করেছে তাকে UTC-তে রূপান্তর করা[cite: 20]
      DateTime startDateTime = DateTime(
        startDate!.year,
        startDate!.month,
        startDate!.day,
        startTime!.hour,
        startTime!.minute,
      ).toUtc();

      DateTime endDateTime = DateTime(
        endDate!.year,
        endDate!.month,
        endDate!.day,
        endTime!.hour,
        endTime!.minute,
      ).toUtc();

      if (endDateTime.isBefore(startDateTime)) {
        Get.snackbar(
          "ত্রুটি",
          "শেষের সময় শুরুর সময়ের আগে হতে পারে না।",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // সুপাবেস থেকে বর্তমান একাডেমি ও ক্লাসের শুধুমাত্র সক্রিয় (is_active = true) পরীক্ষাগুলো আনা[cite: 20]
      final response = await supabase
          .from('exam_schedules')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('is_active', true);

      List existingExams = response ?? [];
      List<Map<String, dynamic>> conflictingExams = [];

      for (var exam in existingExams) {
        // ডাটাবেজের সময়কে পার্স করে UTC-তে রূপান্তর করা[cite: 20]
        DateTime dbStart = DateTime.parse(exam['start_time']).toUtc();
        DateTime dbEnd = DateTime.parse(exam['end_time']).toUtc();

        // ওভারল্যাপ বা কনফ্লিক্ট চেক[cite: 20]
        if (startDateTime.isBefore(dbEnd) && endDateTime.isAfter(dbStart)) {
          conflictingExams.add(exam);
        }
      }

      if (conflictingExams.isNotEmpty) {
        _showConflictDialog(conflictingExams);
        return;
      }

      // কোনো কনফ্লিক্ট না থাকলে সেভ হবে[cite: 20]
      await _saveModelTest(startDateTime, endDateTime, qCount, title);
    } catch (e) {
      debugPrint("Error checking schedule: $e");
      Get.snackbar(
        "ত্রুটি",
        "পরীক্ষার সময় যাচাই করতে সমস্যা হয়েছে: $e",
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

  // বিস্তারিত কারণসহ কনফ্লিক্ট পপআপ দেখানোর ফাংশন
  void _showConflictDialog(List<Map<String, dynamic>> conflicts) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'মডেল টেস্ট তৈরি করা সম্ভব নয়!',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'কারণ: একই শ্রেণিতে (Class: ${widget.className}) এই নির্দিষ্ট সময়ে ইতিমধ্যে অন্য একটি পরীক্ষা বা মডেল টেস্ট নির্ধারিত রয়েছে। ছাত্রছাত্রীরা একই সময়ে দুটি পরীক্ষায় অংশগ্রহণ করতে পারে না।',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.red.shade900,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'বিদ্যমান conflicting পরীক্ষা(গুলো):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: conflicts.length,
                  itemBuilder: (context, index) {
                    var exam = conflicts[index];
                    String examTitle = exam['exam_title'] ?? 'মডেল টেস্ট';
                    String subject = exam['subject_name'] ?? '';
                    String creator = exam['question_creator_name'] ?? 'শিক্ষক';

                    // লোকাল টাইম পার্স করা
                    DateTime sTime = DateTime.parse(
                      exam['start_time'],
                    ).toLocal();
                    DateTime eTime = DateTime.parse(exam['end_time']).toLocal();
                    String formattedStart = DateFormat(
                      'dd MMM, yyyy - hh:mm a',
                    ).format(sTime);
                    String formattedEnd = DateFormat('hh:mm a').format(eTime);

                    return Card(
                      color: Colors.grey.shade100,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• $examTitle ($subject)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'প্রণেতা: $creator',
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              'সময়: $formattedStart হতে $formattedEnd',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
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
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
            ),
            onPressed: () => Get.back(),
            child: const Text('ঠিক আছে', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // মডেল টেস্ট ডাটাবেসে সেভ করার মূল ফাংশন
  Future<void> _saveModelTest(
    DateTime startDateTime,
    DateTime endDateTime,
    int qCount,
    String title,
  ) async {
    try {
      List<String> questionIds = [];

      if (selectedChapter != null && manuallySelectedQuestionIds.isNotEmpty) {
        questionIds = manuallySelectedQuestionIds;
        if (questionIds.length > qCount) {
          questionIds = questionIds.take(qCount).toList();
        }
      } else {
        var query = supabase
            .from('academy_questions')
            .select('id')
            .eq('academy_id', widget.academyId)
            .eq('class_name', widget.className)
            .eq('subject_name', widget.subjectName);

        final questionsRes = await query;
        List allQList = List.from(questionsRes ?? []);

        if (qCount > allQList.length) {
          Get.snackbar(
            "ত্রুটি",
            "পর্যাপ্ত প্রশ্ন নেই। উপলব্ধ প্রশ্ন: ${allQList.length} টি",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        allQList.shuffle();
        List selectedQuestions = allQList.take(qCount).toList();
        questionIds = selectedQuestions.map((q) => q['id'].toString()).toList();
      }

      String creatorId = widget.currentUserId ?? '';
      String creatorName = widget.currentUserName ?? 'Teacher';

      // Supabase-এর exam_schedules টেবিলে সঠিক ISO ফরম্যাটে ডাটা ইনসার্ট করা হলো[cite: 20]
      await supabase.from('exam_schedules').insert({
        'academy_id': widget.academyId,
        'class_name': widget.className,
        'subject_name': widget.subjectName,
        'exam_title': title,
        'chapter_name': selectedChapter,
        'question_count': questionIds.length,
        'selected_question_ids': jsonEncode(questionIds),
        'start_time': startDateTime.toIso8601String(),
        'end_time': endDateTime.toIso8601String(),
        'is_active': true,
        'question_creator_id': creatorId.isEmpty ? null : creatorId,
        'question_creator_name': creatorName,
      });

      Get.back();
      Get.snackbar(
        "সফল",
        "মডেল টেস্ট সফলভাবে তৈরি করা হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint("Error creating model test: $e");
      Get.snackbar(
        "ত্রুটি",
        "মডেল টেস্ট তৈরি করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'নতুন মডেল টেস্ট তৈরি করুন',
          style: TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
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
                        color: Colors.indigo.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: testTitleController,
              decoration: const InputDecoration(
                labelText: 'মডেল টেস্টের নাম (যেমন: ১ম মডেল টেস্ট)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            isLoadingChapters
                ? const Center(child: LinearProgressIndicator())
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedChapter,
                        isExpanded: true,
                        hint: const Text(
                          "নির্দিষ্ট অধ্যায় সিলেক্ট করুন (ঐচ্ছিক)",
                          style: TextStyle(fontSize: 13),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text(
                              "সকল অধ্যায় (পুরো বিষয় থেকে র্যান্ডম)",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          ...availableChaptersData.map((map) {
                            String chName = map['chapter_name'];
                            int chCount = map['count'];
                            return DropdownMenuItem<String>(
                              value: chName,
                              child: Text('$chName (প্রশ্ন আছে: $chCount টি)'),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'এই অধ্যায়ে মোট প্রশ্ন: $selectedChapterQuestionCount টি',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      fontSize: 13,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: _goToQuestionSelectionPage,
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: Text(
                      'প্রশ্ন দেখুন (${manuallySelectedQuestionIds.length}টি সিলেক্টেড)',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: questionCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'পরীক্ষায় মোট কতটি প্রশ্ন থাকবে?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'পরীক্ষার শুরুর সময়:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (pickedDate != null) {
                        setState(() => startDate = pickedDate);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      startDate == null
                          ? 'তারিখ বাছুন'
                          : DateFormat('yyyy-MM-dd').format(startDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (pickedTime != null) {
                        setState(() => startTime = pickedTime);
                      }
                    },
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      startTime == null
                          ? 'সময় বাছুন'
                          : startTime!.format(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'পরীক্ষার শেষ সময়:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (pickedDate != null) {
                        setState(() => endDate = pickedDate);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      endDate == null
                          ? 'তারিখ বাছুন'
                          : DateFormat('yyyy-MM-dd').format(endDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (pickedTime != null) {
                        setState(() => endTime = pickedTime);
                      }
                    },
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      endTime == null ? 'সময় বাছুন' : endTime!.format(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
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
                    : const Text(
                        'মডেল টেস্ট তৈরি করুন',
                        style: TextStyle(
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
}

// ২. আলাদা পেজ: প্রশ্ন সিলেক্ট করার পেজ
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
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> questions = [];
  late Set<String> selectedIds;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    selectedIds = Set.from(widget.initiallySelectedIds);
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final response = await supabase
          .from('academy_questions')
          .select('id, question_text, correct_option')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName)
          .eq('chapter_name', widget.chapterName);

      setState(() {
        questions = List<Map<String, dynamic>>.from(response ?? []);
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching chapter questions: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.chapterName} - প্রশ্ন নির্বাচন',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              Get.back(result: selectedIds.toList());
            },
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
                var q = questions[index];
                String qId = q['id'].toString();
                String qText = q['question_text'] ?? 'প্রশ্ন নেই';
                String correctOpt = q['correct_option'] ?? 'N/A';
                bool isSelected = selectedIds.contains(qId);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 2,
                  child: CheckboxListTile(
                    title: Text(
                      qText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        'সঠিক উত্তর: $correctOpt',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedIds.add(qId);
                        } else {
                          selectedIds.remove(qId);
                        }
                      });
                    },
                  ),
                );
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.indigo.shade50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'মোট সিলেক্টেড: ${selectedIds.length} টি',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Get.back(result: selectedIds.toList());
              },
              child: const Text('নিশ্চিত করুন'),
            ),
          ],
        ),
      ),
    );
  }
}
