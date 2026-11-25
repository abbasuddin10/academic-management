import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/exam_repository.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// আলাদা করা ফাইলটি ইম্পোর্ট করা হলো (আপনার প্রজেক্টের পাথ অনুযায়ী এটি ঠিক করে নেবেন)
import 'create_custom_model_test_view.dart';
import 'model_test_ai_builder_view.dart';
import 'model_test_results_view.dart';
import 'package:academy_management/views/exams/question_create_teacher.dart';

/// Shared validation for both question-bank edit dialogs.
String? validateQuestionInput(
  String questionText,
  List<String> options,
  String correctOption,
) {
  if (questionText.trim().isEmpty) return 'প্রশ্ন খালি রাখা যাবে না।';
  if (options.length < 2 || options.any((item) => item.trim().isEmpty)) {
    return 'প্রতিটি অপশন পূরণ করতে হবে।';
  }
  final normalized = options.map((item) => item.trim().toLowerCase()).toList();
  if (normalized.toSet().length != normalized.length) {
    return 'একই অপশন একাধিকবার দেওয়া যাবে না।';
  }
  if (!['A', 'B', 'C', 'D'].contains(correctOption.trim().toUpperCase())) {
    return 'সঠিক অপশন নির্বাচন করুন।';
  }
  return null;
}

/// Deletes a bank question. Published tests keep their immutable snapshot, so
/// this never corrupts an existing test or a student's recorded answers.
Future<void> confirmDeleteQuestion({
  required SupabaseClient supabase,
  required Map<String, dynamic> question,
  required Future<void> Function() onDeleted,
}) async {
  final confirm = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('প্রশ্ন মুছুন'),
      content: const Text('এই প্রশ্নটি কি সত্যিই মুছে ফেলতে চান?'),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('বাতিল'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Get.back(result: true),
          child: const Text('মুছুন'),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  try {
    await supabase.from('academy_questions').delete().eq('id', question['id']);
    await onDeleted();
    Get.snackbar(
      'সফল',
      'প্রশ্নটি মুছে ফেলা হয়েছে।',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  } catch (e) {
    Get.snackbar(
      'ত্রুটি',
      ModelTestRepository.friendlyError(e),
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
  }
}

// অধ্যায়ের প্রশ্নগুলো দেখানোর জন্য ডেডিকেটেড পেইজ (সার্চ ফিচার সহ)
class ChapterQuestionsView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;
  final String chapterName;

  const ChapterQuestionsView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
    required this.chapterName,
  });

  @override
  State<ChapterQuestionsView> createState() => _ChapterQuestionsViewState();
}

class _ChapterQuestionsViewState extends State<ChapterQuestionsView> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> questions = [];
  List<Map<String, dynamic>> filteredQuestions = [];

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() => isLoading = true);
    try {
      final loaded = await ExamRepository().fetchQuestions(
        academyId: widget.academyId,
        className: widget.className,
        subjectName: widget.subjectName,
        chapterName: widget.chapterName,
      );

      setState(() {
        questions = loaded.map((question) => question.toMap()).toList();
        filteredQuestions = questions;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading questions: $e");
      setState(() => isLoading = false);
    }
  }

  void _filterQuestions(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredQuestions = questions;
      });
    } else {
      setState(() {
        filteredQuestions = questions.where((q) {
          String qText = (q['question_text'] ?? q['question'] ?? '')
              .toLowerCase();
          String optA = (q['option_a'] ?? '').toLowerCase();
          String optB = (q['option_b'] ?? '').toLowerCase();
          String optC = (q['option_c'] ?? '').toLowerCase();
          String optD = (q['option_d'] ?? '').toLowerCase();
          String searchLower = query.toLowerCase();

          return qText.contains(searchLower) ||
              optA.contains(searchLower) ||
              optB.contains(searchLower) ||
              optC.contains(searchLower) ||
              optD.contains(searchLower);
        }).toList();
      });
    }
  }

  List<String> _getOptions(Map<String, dynamic> qData) {
    return [
      qData['option_a']?.toString() ?? '',
      qData['option_b']?.toString() ?? '',
      qData['option_c']?.toString() ?? '',
      qData['option_d']?.toString() ?? '',
    ];
  }

  Future<void> _editQuestion(Map<String, dynamic> qData) async {
    final textController = TextEditingController(
      text: qData['question_text'] ?? qData['question'] ?? '',
    );

    List<String> optionsList = _getOptions(qData);

    List<TextEditingController> optionControllers = optionsList
        .map((opt) => TextEditingController(text: opt))
        .toList();

    String currentCorrectOption =
        (qData['correct_option'] ?? qData['correctAnswer'] ?? 'A')
            .toString()
            .trim()
            .toUpperCase();

    await Get.dialog(
      AlertDialog(
        title: const Text('প্রশ্ন এডিট করুন', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'প্রশ্ন:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: textController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'অপশনসমূহ:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...List.generate(optionControllers.length, (index) {
                  String optLetter = String.fromCharCode(65 + index);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '$optLetter. ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: TextField(
                            controller: optionControllers[index],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text(
                  'সঠিক অপশন:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: ['A', 'B', 'C', 'D'].contains(currentCorrectOption)
                      ? currentCorrectOption
                      : 'A',
                  items: ['A', 'B', 'C', 'D'].map((val) {
                    return DropdownMenuItem(value: val, child: Text(val));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      currentCorrectOption = val;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final options = optionControllers
                  .map((controller) => controller.text.trim())
                  .toList();
              final validation = validateQuestionInput(
                textController.text,
                options,
                currentCorrectOption,
              );
              if (validation != null) {
                Get.snackbar(
                  'সতর্কতা',
                  validation,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              try {
                // question_hash is kept accurate by the DB trigger in 0007.
                await supabase
                    .from('academy_questions')
                    .update({
                      'question_text': textController.text.trim(),
                      'option_a': options[0],
                      'option_b': options[1],
                      'option_c': options[2],
                      'option_d': options[3],
                      'correct_option': currentCorrectOption,
                    })
                    .eq('id', qData['id']);

                Get.back();
                Get.snackbar("সফল", "প্রশ্নটি সফলভাবে আপডেট করা হয়েছে।");
                _loadQuestions();
              } catch (e) {
                debugPrint("Error updating question: $e");
                Get.snackbar("ত্রুটি", "প্রশ্ন আপডেট করতে সমস্যা হয়েছে।");
              }
            },
            child: Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'প্রশ্ন সার্চ করুন...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: _filterQuestions,
              )
            : Text(widget.chapterName, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  filteredQuestions = questions;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredQuestions.isEmpty
          ? const Center(child: Text('কোনো প্রশ্ন পাওয়া যায়নি।'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredQuestions.length,
              itemBuilder: (context, qIndex) {
                var qData = filteredQuestions[qIndex];
                String questionText =
                    qData['question_text'] ?? qData['question'] ?? '';

                List<String> optionsList = _getOptions(qData);

                String correctOptionKey =
                    (qData['correct_option'] ?? qData['correctAnswer'] ?? '')
                        .toString()
                        .trim()
                        .toUpperCase();

                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppTheme.borderOf(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${qIndex + 1}. $questionText',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 18,
                                color: Colors.orange,
                              ),
                              onPressed: () => _editQuestion(qData),
                            ),
                            IconButton(
                              tooltip: 'প্রশ্ন মুছুন',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              onPressed: () => confirmDeleteQuestion(
                                supabase: supabase,
                                question: qData,
                                onDeleted: _loadQuestions,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(optionsList.length, (optIndex) {
                          String optionLetter = String.fromCharCode(
                            65 + optIndex,
                          );
                          bool isCorrect = optionLetter == correctOptionKey;

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 2),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? AppTheme.tileOf(context, Colors.green)
                                  : AppTheme.altSurfaceOf(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCorrect
                                    ? AppTheme.tileOf(context, Colors.green)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCorrect
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 16,
                                  color: isCorrect ? Colors.green : Colors.grey,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '$optionLetter. ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCorrect
                                        ? AppTheme.tileInkOf(
                                            context,
                                            Colors.green,
                                          )
                                        : AppTheme.inkOf(context),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    optionsList[optIndex],
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isCorrect
                                          ? AppTheme.tileInkOf(
                                              context,
                                              Colors.green,
                                            )
                                          : AppTheme.inkOf(context),
                                      fontWeight: isCorrect
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// সকল প্রশ্ন একসাথে দেখানোর জন্য ডেডিকেটেড পেইজ (সার্চ ফিচার সহ)
class AllSubjectQuestionsView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;

  const AllSubjectQuestionsView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
  });

  @override
  State<AllSubjectQuestionsView> createState() =>
      _AllSubjectQuestionsViewState();
}

class _AllSubjectQuestionsViewState extends State<AllSubjectQuestionsView> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> questions = [];
  List<Map<String, dynamic>> filteredQuestions = [];

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllQuestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllQuestions() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('academy_questions')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName);

      setState(() {
        questions = List<Map<String, dynamic>>.from(response);
        filteredQuestions = questions;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading all questions: $e");
      setState(() => isLoading = false);
    }
  }

  void _filterQuestions(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredQuestions = questions;
      });
    } else {
      setState(() {
        filteredQuestions = questions.where((q) {
          String qText = (q['question_text'] ?? q['question'] ?? '')
              .toLowerCase();
          String optA = (q['option_a'] ?? '').toLowerCase();
          String optB = (q['option_b'] ?? '').toLowerCase();
          String optC = (q['option_c'] ?? '').toLowerCase();
          String optD = (q['option_d'] ?? '').toLowerCase();
          String searchLower = query.toLowerCase();

          return qText.contains(searchLower) ||
              optA.contains(searchLower) ||
              optB.contains(searchLower) ||
              optC.contains(searchLower) ||
              optD.contains(searchLower);
        }).toList();
      });
    }
  }

  List<String> _getOptions(Map<String, dynamic> qData) {
    return [
      qData['option_a']?.toString() ?? '',
      qData['option_b']?.toString() ?? '',
      qData['option_c']?.toString() ?? '',
      qData['option_d']?.toString() ?? '',
    ];
  }

  Future<void> _editQuestion(Map<String, dynamic> qData) async {
    final textController = TextEditingController(
      text: qData['question_text'] ?? qData['question'] ?? '',
    );

    List<String> optionsList = _getOptions(qData);

    List<TextEditingController> optionControllers = optionsList
        .map((opt) => TextEditingController(text: opt))
        .toList();

    String currentCorrectOption =
        (qData['correct_option'] ?? qData['correctAnswer'] ?? 'A')
            .toString()
            .trim()
            .toUpperCase();

    await Get.dialog(
      AlertDialog(
        title: const Text('প্রশ্ন এডিট করুন', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'প্রশ্ন:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: textController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'অপশনসমূহ:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...List.generate(optionControllers.length, (index) {
                  String optLetter = String.fromCharCode(65 + index);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '$optLetter. ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: TextField(
                            controller: optionControllers[index],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text(
                  'সঠিক অপশন:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: ['A', 'B', 'C', 'D'].contains(currentCorrectOption)
                      ? currentCorrectOption
                      : 'A',
                  items: ['A', 'B', 'C', 'D'].map((val) {
                    return DropdownMenuItem(value: val, child: Text(val));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      currentCorrectOption = val;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final options = optionControllers
                  .map((controller) => controller.text.trim())
                  .toList();
              final validation = validateQuestionInput(
                textController.text,
                options,
                currentCorrectOption,
              );
              if (validation != null) {
                Get.snackbar(
                  'সতর্কতা',
                  validation,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              try {
                // question_hash is kept accurate by the DB trigger in 0007.
                await supabase
                    .from('academy_questions')
                    .update({
                      'question_text': textController.text.trim(),
                      'option_a': options[0],
                      'option_b': options[1],
                      'option_c': options[2],
                      'option_d': options[3],
                      'correct_option': currentCorrectOption,
                    })
                    .eq('id', qData['id']);

                Get.back();
                Get.snackbar("সফল", "প্রশ্নটি সফলভাবে আপডেট করা হয়েছে।");
                _loadAllQuestions();
              } catch (e) {
                debugPrint("Error updating question: $e");
                Get.snackbar("ত্রুটি", "প্রশ্ন আপডেট করতে সমস্যা হয়েছে।");
              }
            },
            child: Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'সকল প্রশ্ন সার্চ করুন...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: _filterQuestions,
              )
            : Text(
                'সকল প্রশ্ন: ${widget.subjectName}',
                style: const TextStyle(fontSize: 16),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  filteredQuestions = questions;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredQuestions.isEmpty
          ? const Center(child: Text('এই বিষয়ের কোনো প্রশ্ন নেই।'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredQuestions.length,
              itemBuilder: (context, qIndex) {
                var qData = filteredQuestions[qIndex];
                String questionText =
                    qData['question_text'] ?? qData['question'] ?? '';

                List<String> optionsList = _getOptions(qData);

                String correctOptionKey =
                    (qData['correct_option'] ?? qData['correctAnswer'] ?? '')
                        .toString()
                        .trim()
                        .toUpperCase();

                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppTheme.borderOf(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${qIndex + 1}. $questionText',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 18,
                                color: Colors.orange,
                              ),
                              onPressed: () => _editQuestion(qData),
                            ),
                            IconButton(
                              tooltip: 'প্রশ্ন মুছুন',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              onPressed: () => confirmDeleteQuestion(
                                supabase: supabase,
                                question: qData,
                                onDeleted: _loadAllQuestions,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(optionsList.length, (optIndex) {
                          String optionLetter = String.fromCharCode(
                            65 + optIndex,
                          );
                          bool isCorrect = optionLetter == correctOptionKey;

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 2),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? AppTheme.tileOf(context, Colors.green)
                                  : AppTheme.altSurfaceOf(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCorrect
                                    ? AppTheme.tileOf(context, Colors.green)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCorrect
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 16,
                                  color: isCorrect ? Colors.green : Colors.grey,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '$optionLetter. ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCorrect
                                        ? AppTheme.tileInkOf(
                                            context,
                                            Colors.green,
                                          )
                                        : AppTheme.inkOf(context),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    optionsList[optIndex],
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isCorrect
                                          ? AppTheme.tileInkOf(
                                              context,
                                              Colors.green,
                                            )
                                          : AppTheme.inkOf(context),
                                      fontWeight: isCorrect
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// মূল ModelTestView ক্লাস
class ModelTestView extends StatefulWidget {
  final String academyId;
  final String? currentUserId;
  final String? currentUserName;

  const ModelTestView({
    super.key,
    required this.academyId,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<ModelTestView> createState() => _ModelTestViewState();
}

class _ModelTestViewState extends State<ModelTestView> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool isLoadingClasses = false;
  bool isLoadingSubjects = false;
  bool isLoadingTests = false;

  List<String> availableClasses = [];
  String? selectedClass;

  List<String> availableSubjects = [];
  String? selectedSubject;

  List<Map<String, dynamic>> modelTests = [];
  final Map<String, ModelTest> _testById = <String, ModelTest>{};
  final _modelTestRepository = ModelTestRepository();
  int totalSubjectQuestions = 0;

  final Map<String, int> _selectedButtonIndices = {};

  @override
  void initState() {
    super.initState();
    _loadAcademyClassesFromRoutine();
  }

  Future<void> _loadAcademyClassesFromRoutine() async {
    setState(() => isLoadingClasses = true);
    try {
      final response = await supabase
          .from('exam_routines')
          .select('class_name')
          .eq('academy_id', widget.academyId);

      Set<String> uniqueClasses = {};
      for (var item in (response as List)) {
        String className = item['class_name']?.toString().trim() ?? '';
        if (className.isNotEmpty) {
          uniqueClasses.add(className);
        }
      }

      setState(() {
        availableClasses = uniqueClasses.toList();
        availableClasses.sort();
      });
    } catch (e) {
      debugPrint("Error loading classes from routine: $e");
    } finally {
      setState(() => isLoadingClasses = false);
    }
  }

  Future<void> _loadSubjectsForSelectedClass(String className) async {
    setState(() => isLoadingSubjects = true);
    try {
      final response = await supabase
          .from('exam_routines')
          .select('subject_name')
          .eq('academy_id', widget.academyId)
          .eq('class_name', className);

      Set<String> uniqueSubjects = {};
      for (var item in (response as List)) {
        String subjectName = item['subject_name']?.toString().trim() ?? '';
        if (subjectName.isNotEmpty) {
          uniqueSubjects.add(subjectName);
        }
      }

      setState(() {
        availableSubjects = uniqueSubjects.toList();
        availableSubjects.sort();
        selectedSubject = null;
        modelTests = [];
        totalSubjectQuestions = 0;
        _selectedButtonIndices.clear();
      });
    } catch (e) {
      debugPrint("Error loading subjects: $e");
    } finally {
      setState(() => isLoadingSubjects = false);
    }
  }

  Future<void> _loadTotalQuestionsCount() async {
    if (selectedClass == null || selectedSubject == null) return;
    try {
      final response = await supabase
          .from('academy_questions')
          .select('id')
          .eq('academy_id', widget.academyId)
          .eq('class_name', selectedClass!)
          .eq('subject_name', selectedSubject!);

      setState(() {
        totalSubjectQuestions = (response as List).length;
      });
    } catch (e) {
      debugPrint("Error loading total questions count: $e");
    }
  }

  Future<void> _loadModelTests() async {
    if (selectedClass == null || selectedSubject == null) return;

    setState(() => isLoadingTests = true);
    await _loadTotalQuestionsCount();

    try {
      final tests = await _modelTestRepository.fetchTests(
        academyId: widget.academyId,
        className: selectedClass,
        // Staff must see drafts so they can edit/publish them. Student screens
        // leave this false and only ever receive published/expired tests.
        includeUnpublished: true,
      );
      final scoped = tests
          .where((test) => test.subjectName == selectedSubject)
          .toList();

      final loaded = <Map<String, dynamic>>[];
      _testById.clear();
      for (final test in scoped) {
        _testById[test.id] = test;
        loaded.add({
          'id': test.id,
          'exam_title': test.examTitle,
          'start_time': test.startAt?.toIso8601String(),
          'end_time': test.endAt?.toIso8601String(),
          'is_active': test.isPublished,
          'status': test.status,
          'question_count': test.questionCount,
          'question_creator_id': test.creatorId,
          'question_creator_name': test.creatorName,
          'duration_minutes': test.durationMinutes,
          'total_marks': test.totalMarks,
        });
      }
      if (!mounted) return;
      setState(() {
        modelTests = loaded;
        _selectedButtonIndices.clear();
      });
    } catch (e) {
      debugPrint('Error loading model tests: $e');
      if (mounted) {
        Get.snackbar(
          'ত্রুটি',
          ModelTestRepository.friendlyError(e),
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => isLoadingTests = false);
    }
  }

  // পরীক্ষার নাম এডিট করার ফাংশন
  /// Opens the full editor (title, schedule, duration, marks, questions,
  /// publish state) instead of the old title-only dialog.
  Future<void> _editTest(Map<String, dynamic> test) async {
    final modelTest = _testById[test['id']?.toString()];
    if (modelTest == null) {
      Get.snackbar(
        'ত্রুটি',
        'পরীক্ষার তথ্য পাওয়া যায়নি।',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    final saved = await Get.to(
      () => CreateCustomModelTestView(
        academyId: widget.academyId,
        className: selectedClass!,
        subjectName: selectedSubject!,
        totalSubjectQuestions: totalSubjectQuestions,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        existingTest: modelTest,
      ),
    );
    if (saved == true) _loadModelTests();
  }

  Future<void> _openResults(Map<String, dynamic> test) async {
    final modelTest = _testById[test['id']?.toString()];
    if (modelTest == null) return;
    await Get.to(() => ModelTestResultsView(test: modelTest));
  }

  void _openAiBuilder() {
    if (selectedClass == null || selectedClass!.trim().isEmpty) {
      Get.snackbar(
        'প্রথমে ক্লাস বাছুন',
        'AI বিল্ডার ব্যবহার করতে উপর থেকে ক্লাস সিলেক্ট করুন।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    Get.to(
      () => ModelTestAiBuilderView(
        academyId: widget.academyId,
        className: selectedClass!,
        subjectName: selectedSubject,
        availableSubjects: availableSubjects,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        existingTests: _testById.values.toList(),
        onCreated: () {
          _loadTotalQuestionsCount();
          _loadModelTests();
        },
      ),
    );
  }

  Future<void> _openCreateTest() async {
    await Get.to(
      () => CreateCustomModelTestView(
        academyId: widget.academyId,
        className: selectedClass!,
        subjectName: selectedSubject!,
        totalSubjectQuestions: totalSubjectQuestions,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
      ),
    );
    _loadModelTests();
  }

  Future<void> _openCreateQuestion() async {
    await Get.to(
      () => CreateTestView(
        academyId: widget.academyId,
        className: selectedClass!,
        subjectName: selectedSubject!,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        onSaved: () {
          // Immediately refresh the visible question count and chapter list
          // behind the form.
          _loadTotalQuestionsCount();
        },
      ),
    );
    _loadTotalQuestionsCount();
    _loadModelTests();
  }

  Future<void> _publishTest(Map<String, dynamic> test) async {
    try {
      await _modelTestRepository.setStatus(test['id'].toString(), 'published');
      Get.snackbar(
        'সফল',
        'পরীক্ষাটি প্রকাশিত হয়েছে।',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      _loadModelTests();
    } catch (e) {
      Get.snackbar(
        'ত্রুটি',
        ModelTestRepository.friendlyError(e),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ডিলেট লজিক ফাংশন
  Future<void> _deleteExamCard(Map<String, dynamic> test) async {
    String testTitle = test['exam_title'];
    dynamic examId = test['id'];
    dynamic creatorId = test['question_creator_id'];
    String? creatorName = test['question_creator_name'];

    String? currentUserIdStr = widget.currentUserId?.toString().trim();
    String? creatorIdStr = creatorId?.toString().trim();

    bool isCreator = false;

    if (currentUserIdStr != null &&
        creatorIdStr != null &&
        currentUserIdStr == creatorIdStr) {
      isCreator = true;
    } else if (creatorIdStr == null || creatorIdStr.isEmpty) {
      isCreator = true;
    }

    if (isCreator) {
      Get.defaultDialog(
        title: "পরীক্ষা ডিলিট",
        middleText: "$testTitle পরীক্ষাটি কি আপনি সত্যিই ডিলিট করতে চান?",
        textConfirm: "হ্যাঁ, ডিলিট",
        textCancel: "না",
        confirmTextColor: Colors.white,
        buttonColor: Colors.red,
        onConfirm: () async {
          Get.back();
          try {
            await _modelTestRepository.deleteTest(
              testId: examId.toString(),
              academyId: widget.academyId,
            );

            Get.snackbar(
              "সফল",
              "পরীক্ষাটি সফলভাবে ডিলিট করা হয়েছে।",
              backgroundColor: Colors.green,
              colorText: Colors.white,
            );
            _loadModelTests();
          } catch (e) {
            debugPrint("Error deleting exam: $e");
            Get.snackbar(
              "ত্রুটি",
              "পরীক্ষা ডিলিট করতে সমস্যা হয়েছে: $e",
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
        },
      );
    } else {
      String nameToShow =
          (creatorName != null && creatorName.toString().isNotEmpty)
          ? creatorName
          : 'অন্য কোনো শিক্ষক';

      Get.defaultDialog(
        title: "ডিলিট করার অনুমতি নেই",
        middleText:
            "এই পরীক্ষাটি আপনি তৈরি করেননি। এটি তৈরি করেছেন: $nameToShow। পরীক্ষাটি ডিলিট করতে চাইলে উনার সাথে যোগাযোগ করুন।",
        textConfirm: "ঠিক আছে",
        confirmTextColor: Colors.white,
        buttonColor: AppTheme.tileInkOf(context, Colors.indigo),
        onConfirm: () {
          Get.back();
        },
      );
    }
  }

  // পরীক্ষা বাতিল করার লজিক (ক্রিয়েটর চেক সহ)
  Future<void> _cancelExam(Map<String, dynamic> test) async {
    String testTitle = test['exam_title'];
    dynamic examId = test['id'];
    dynamic creatorId = test['question_creator_id'];
    String? creatorName = test['question_creator_name'];

    String? currentUserIdStr = widget.currentUserId?.toString().trim();
    String? creatorIdStr = creatorId?.toString().trim();

    bool isCreator = false;

    if (currentUserIdStr != null &&
        creatorIdStr != null &&
        currentUserIdStr == creatorIdStr) {
      isCreator = true;
    } else if (creatorIdStr == null || creatorIdStr.isEmpty) {
      isCreator = true;
    }

    if (isCreator) {
      Get.defaultDialog(
        title: "পরীক্ষা বাতিল",
        middleText: "$testTitle পরীক্ষাটি কি আপনি সত্যিই বাতিল করতে চান?",
        textConfirm: "হ্যাঁ, বাতিল",
        textCancel: "না",
        confirmTextColor: Colors.white,
        buttonColor: Colors.red,
        onConfirm: () async {
          Get.back();
          try {
            await _modelTestRepository.setStatus(
              examId.toString(),
              'cancelled',
            );

            Get.snackbar(
              "সফল",
              "পরীক্ষাটি সফলভাবে বাতিল করা হয়েছে।",
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
            _loadModelTests();
          } catch (e) {
            debugPrint("Error canceling exam: $e");
            Get.snackbar("ত্রুটি", "পরীক্ষা বাতিল করতে সমস্যা হয়েছে।");
          }
        },
      );
    } else {
      String nameToShow =
          (creatorName != null && creatorName.toString().isNotEmpty)
          ? creatorName
          : 'অন্য কোনো শিক্ষক';

      Get.defaultDialog(
        title: "বাতিল করার অনুমতি নেই",
        middleText:
            "এই পরীক্ষাটি আপনি তৈরি করেননি। এটি তৈরি করেছেন: $nameToShow। পরীক্ষাটি বাতিল করতে চাইলে উনার সাথে যোগাযোগ করুন।",
        textConfirm: "ঠিক আছে",
        confirmTextColor: Colors.white,
        buttonColor: AppTheme.tileInkOf(context, Colors.indigo),
        onConfirm: () {
          Get.back();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'মডেল টেস্ট ও খাতা মূল্যায়ন',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'AI দিয়ে মডেল টেস্ট তৈরি করুন',
            onPressed: _openAiBuilder,
            icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: isLoadingClasses
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceOf(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.borderOf(context),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: AppTheme.altSurfaceOf(context),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedClass,
                              isExpanded: true,
                              hint: Text(
                                "ক্লাস সিলেক্ট করুন",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedOf(context),
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
                                  _loadSubjectsForSelectedClass(newValue);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.borderOf(context),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: AppTheme.altSurfaceOf(context),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedSubject,
                              isExpanded: true,
                              hint: Text(
                                "বিষয় সিলেক্ট করুন",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedOf(context),
                                ),
                              ),
                              items: availableSubjects.map((String subject) {
                                return DropdownMenuItem<String>(
                                  value: subject,
                                  child: Text(
                                    subject,
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
                                    selectedSubject = newValue;
                                  });
                                  _loadModelTests();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: (selectedClass == null || selectedSubject == null)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 56,
                                  color: AppTheme.tileOf(
                                    context,
                                    Colors.indigo,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'দয়া করে ওপর থেকে ক্লাস এবং বিষয় সিলেক্ট করুন',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.mutedOf(context),
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
                                      '$selectedClass - $selectedSubject',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.tileInkOf(
                                          context,
                                          Colors.indigo,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.tileOf(
                                        context,
                                        Colors.indigo,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'মোট মডেল টেস্ট: ${modelTests.length}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.tileInkOf(
                                          context,
                                          Colors.indigo,
                                        ),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: isLoadingTests || isLoadingSubjects
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : ListView.builder(
                                        // Keeps the last card clear of the two
                                        // floating action buttons at the bottom.
                                        padding: const EdgeInsets.only(
                                          bottom: 96,
                                        ),
                                        itemCount: modelTests.length + 1,
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            return Container(
                                              margin: EdgeInsets.only(
                                                bottom: 14,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.surfaceOf(
                                                  context,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: AppTheme.tileOf(
                                                    context,
                                                    Colors.indigo,
                                                  ),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.indigo
                                                        .withValues(
                                                          alpha: 0.04,
                                                        ),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 14,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: EdgeInsets.all(
                                                        10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.tileOf(
                                                          context,
                                                          Colors.indigo,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        Icons.library_books,
                                                        color:
                                                            AppTheme.tileInkOf(
                                                              context,
                                                              Colors.indigo,
                                                            ),
                                                        size: 22,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'সকল প্রশ্ন দেখুন',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 15,
                                                              color:
                                                                  AppTheme.mutedOf(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            'মোট প্রশ্ন: $totalSubjectQuestions টি',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey
                                                                  .shade600,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            AppTheme.tileInkOf(
                                                              context,
                                                              Colors.indigo,
                                                            ),
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
                                                              horizontal: 14,
                                                              vertical: 10,
                                                            ),
                                                      ),
                                                      onPressed: () {
                                                        Get.to(
                                                          () => AllSubjectQuestionsView(
                                                            academyId: widget
                                                                .academyId,
                                                            className:
                                                                selectedClass!,
                                                            subjectName:
                                                                selectedSubject!,
                                                          ),
                                                        );
                                                      },
                                                      child: const Text(
                                                        'ভিউ করুন',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }

                                          var test = modelTests[index - 1];
                                          String testTitle = test['exam_title'];
                                          String? creatorName =
                                              test['question_creator_name'];
                                          int questionCount =
                                              test['question_count'];

                                          String? startTimeStr =
                                              test['start_time'];
                                          String? endTimeStr = test['end_time'];
                                          bool isActive =
                                              test['is_active'] ?? false;

                                          String formattedTimeText =
                                              'সময় নির্ধারণ করা হয়নি';
                                          if (startTimeStr != null &&
                                              endTimeStr != null) {
                                            // লোকल টাইমজোন অনুযায়ী কনভার্ট করার জন্য .toLocal() ব্যবহার করা হয়েছে
                                            DateTime startDt = DateTime.parse(
                                              startTimeStr,
                                            ).toLocal();
                                            DateTime endDt = DateTime.parse(
                                              endTimeStr,
                                            ).toLocal();

                                            // ১২ ঘন্টার ফরম্যাট (AM/PM) এবং লোকাল টাইম দেখানোর জন্য
                                            formattedTimeText =
                                                'শুরু: ${DateFormat('dd MMM, hh:mm a').format(startDt)}  •  শেষ: ${DateFormat('dd MMM, hh:mm a').format(endDt)}';
                                          }

                                          return Container(
                                            margin: EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceOf(
                                                context,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: AppTheme.borderOf(
                                                  context,
                                                ),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.02),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                14.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                testTitle,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 15,
                                                                  height: 1.25,
                                                                ),
                                                              ),
                                                            ),
                                                            InkWell(
                                                              onTap: () =>
                                                                  _editTest(
                                                                    test,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                              child: Padding(
                                                                padding:
                                                                    EdgeInsets.all(
                                                                      4.0,
                                                                    ),
                                                                child: Icon(
                                                                  Icons.edit,
                                                                  size: 16,
                                                                  color: AppTheme.tileInkOf(
                                                                    context,
                                                                    Colors
                                                                        .orange,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? AppTheme.tileOf(
                                                                  context,
                                                                  Colors.green,
                                                                )
                                                              : AppTheme.altSurfaceOf(
                                                                  context,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                          border: Border.all(
                                                            color: isActive
                                                                ? AppTheme.tileOf(
                                                                    context,
                                                                    Colors
                                                                        .green,
                                                                  )
                                                                : AppTheme.borderOf(
                                                                    context,
                                                                  ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          switch (test['status']
                                                              ?.toString()) {
                                                            'draft' => 'খসড়া',
                                                            'cancelled' =>
                                                              'বাতিল',
                                                            'expired' => 'শেষ',
                                                            _ =>
                                                              isActive
                                                                  ? 'Active'
                                                                  : 'Inactive',
                                                          },
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isActive
                                                                ? AppTheme.tileInkOf(
                                                                    context,
                                                                    Colors
                                                                        .green,
                                                                  )
                                                                : Colors
                                                                      .grey
                                                                      .shade700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'প্রশ্ন সংখ্যা: $questionCount টি',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.schedule,
                                                        size: 14,
                                                        color: Colors
                                                            .grey
                                                            .shade500,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          formattedTimeText,
                                                          style: TextStyle(
                                                            fontSize: 11.5,
                                                            color: Colors
                                                                .grey
                                                                .shade700,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.person_outline,
                                                        size: 14,
                                                        color: Colors
                                                            .grey
                                                            .shade500,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          'প্রণেতা (স্যার): ${creatorName ?? 'অজানা'}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 11.5,
                                                            color: Colors
                                                                .grey
                                                                .shade700,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  const Divider(
                                                    height: 1,
                                                    color: Color(0xFFF1F5F9),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Wrap(
                                                      alignment:
                                                          WrapAlignment.end,
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      children: [
                                                        _ModelTestActionButton(
                                                          icon: Icons
                                                              .assignment_outlined,
                                                          label: 'ফলাফল',
                                                          color: Colors.indigo,
                                                          onPressed: () =>
                                                              _openResults(
                                                                test,
                                                              ),
                                                        ),
                                                        if (test['status'] ==
                                                            'draft')
                                                          _ModelTestActionButton(
                                                            icon: Icons.publish,
                                                            label:
                                                                'প্রকাশ করুন',
                                                            color: Colors.green,
                                                            onPressed: () =>
                                                                _publishTest(
                                                                  test,
                                                                ),
                                                          ),
                                                        _ModelTestActionButton(
                                                          icon: Icons
                                                              .delete_outline,
                                                          label: 'ডিলিট',
                                                          color: Colors
                                                              .red
                                                              .shade700,
                                                          onPressed: () {
                                                            _deleteExamCard(
                                                              test,
                                                            );
                                                          },
                                                        ),
                                                        if (isActive)
                                                          _ModelTestActionButton(
                                                            icon: Icons
                                                                .stop_circle_outlined,
                                                            label: 'বন্ধ করুন',
                                                            color:
                                                                Colors.orange,
                                                            onPressed: () {
                                                              _cancelExam(test);
                                                            },
                                                          ),
                                                      ],
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
                ),
              ],
            ),
      floatingActionButton: (selectedClass == null || selectedSubject == null)
          ? null
          : Builder(
              builder: (context) {
                final isCompact = MediaQuery.sizeOf(context).width < 400;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'createTestBtn',
                      onPressed: _openCreateTest,
                      backgroundColor: Colors.teal.shade700,
                      elevation: 2,
                      icon: const Icon(
                        Icons.assignment_add,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'মডেল টেস্ট তৈরি',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isCompact)
                      FloatingActionButton(
                        heroTag: 'createQuestionBtn',
                        onPressed: _openCreateQuestion,
                        tooltip: 'নতুন প্রশ্ন তৈরি',
                        backgroundColor: AppTheme.tileInkOf(
                          context,
                          Colors.indigo,
                        ),
                        elevation: 2,
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 22,
                        ),
                      )
                    else
                      FloatingActionButton.extended(
                        heroTag: 'createQuestionBtn',
                        onPressed: _openCreateQuestion,
                        backgroundColor: AppTheme.tileInkOf(
                          context,
                          Colors.indigo,
                        ),
                        elevation: 2,
                        icon: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'নতুন প্রশ্ন তৈরি',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// Compact, wrap-safe action button used on model test cards. A [Wrap] parent
/// lets these chips flow onto a second line instead of overflowing on narrow
/// screens.
class _ModelTestActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ModelTestActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.05),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
