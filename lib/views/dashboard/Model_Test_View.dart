import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// আলাদা করা ফাইলটি ইম্পোর্ট করা হলো (আপনার প্রজেক্টের পাথ অনুযায়ী এটি ঠিক করে নেবেন)
import 'create_custom_model_test_view.dart';
import 'package:academy_management/views/dashboard/question_create_teacher.dart';

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
      final response = await supabase
          .from('academy_questions')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName)
          .eq('chapter_name', widget.chapterName);

      setState(() {
        questions = List<Map<String, dynamic>>.from(response ?? []);
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
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await supabase
                    .from('academy_questions')
                    .update({
                      'question_text': textController.text.trim(),
                      'option_a': optionControllers[0].text.trim(),
                      'option_b': optionControllers[1].text.trim(),
                      'option_c': optionControllers[2].text.trim(),
                      'option_d': optionControllers[3].text.trim(),
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
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade800,
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
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
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
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(optionsList.length, (optIndex) {
                          String optionLetter = String.fromCharCode(
                            65 + optIndex,
                          );
                          bool isCorrect = optionLetter == correctOptionKey;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? Colors.green.shade50
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCorrect
                                    ? Colors.green.shade300
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
                                const SizedBox(width: 8),
                                Text(
                                  '$optionLetter. ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCorrect
                                        ? Colors.green.shade900
                                        : Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    optionsList[optIndex],
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isCorrect
                                          ? Colors.green.shade900
                                          : Colors.black87,
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
        questions = List<Map<String, dynamic>>.from(response ?? []);
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
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await supabase
                    .from('academy_questions')
                    .update({
                      'question_text': textController.text.trim(),
                      'option_a': optionControllers[0].text.trim(),
                      'option_b': optionControllers[1].text.trim(),
                      'option_c': optionControllers[2].text.trim(),
                      'option_d': optionControllers[3].text.trim(),
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
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade800,
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
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
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
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(optionsList.length, (optIndex) {
                          String optionLetter = String.fromCharCode(
                            65 + optIndex,
                          );
                          bool isCorrect = optionLetter == correctOptionKey;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? Colors.green.shade50
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCorrect
                                    ? Colors.green.shade300
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
                                const SizedBox(width: 8),
                                Text(
                                  '$optionLetter. ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCorrect
                                        ? Colors.green.shade900
                                        : Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    optionsList[optIndex],
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isCorrect
                                          ? Colors.green.shade900
                                          : Colors.black87,
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
// মূল ModelTestView ক্লাস
class ModelTestView extends StatefulWidget {
  final String academyId;

  const ModelTestView({super.key, required this.academyId});

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
      if (response != null) {
        for (var item in (response as List)) {
          String className = item['class_name']?.toString().trim() ?? '';
          if (className.isNotEmpty) {
            uniqueClasses.add(className);
          }
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
      if (response != null) {
        for (var item in (response as List)) {
          String subjectName = item['subject_name']?.toString().trim() ?? '';
          if (subjectName.isNotEmpty) {
            uniqueSubjects.add(subjectName);
          }
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

  // মোট প্রশ্নের সংখ্যা বের করার জন্য
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

  // ইউজারদের তৈরি করা বা নির্ধারিত মডেল টেস্টগুলো লোড করার জন্য
  Future<void> _loadModelTests() async {
    if (selectedClass == null || selectedSubject == null) return;

    setState(() => isLoadingTests = true);
    await _loadTotalQuestionsCount();

    try {
      // এখানে exam_schedules বা আপনার মডেল টেস্ট টেবিল থেকে ডেটা ফেচ করা হচ্ছে
      // যেখানে ইউজার কর্তৃক তৈরিকৃত বা শিডিউল করা মডেল টেস্টগুলো থাকবে
      final response = await supabase
          .from('exam_schedules')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('class_name', selectedClass!)
          .eq('subject_name', selectedSubject!);

      List<Map<String, dynamic>> loadedTests = [];
      if (response != null) {
        DateTime now = DateTime.now();
        for (var schedule in (response as List)) {
          bool isActiveFromDb = schedule['is_active'] ?? false;
          String? endTimeStr = schedule['end_time'];

          if (endTimeStr != null) {
            DateTime endDt = DateTime.parse(endTimeStr);
            if (endDt.isBefore(now) && isActiveFromDb) {
              isActiveFromDb = false;
              // ডেটাবেজে মেয়াদ শেষ হলে এটি আপডেট করে দেওয়া হচ্ছে
              await supabase
                  .from('exam_schedules')
                  .update({'is_active': false})
                  .eq('id', schedule['id']);
            }
          }

          loadedTests.add({
            'exam_title': schedule['exam_title'] ?? 'নামবিহীন মডেল টেস্ট',
            'start_time': schedule['start_time'],
            'end_time': endTimeStr,
            'is_active': isActiveFromDb,
            'question_count':
                schedule['question_count'] ??
                0, // যদি টেবিলে কোয়েশ্চেন কাউন্ট থাকে
          });
        }
      }

      setState(() {
        modelTests = loadedTests;
        _selectedButtonIndices.clear();
      });
    } catch (e) {
      debugPrint("Error loading model tests: $e");
    } finally {
      setState(() => isLoadingTests = false);
    }
  }

  Future<void> _setExamSchedule(String testTitle) async {
    DateTime? startDate;
    TimeOfDay? startTime;

    DateTime? endDate;
    TimeOfDay? endTime;

    await Get.dialog(
      AlertDialog(
        title: Text(
          '$testTitle\nপরীক্ষার সময় নির্ধারণ করুন',
          style: const TextStyle(fontSize: 16),
        ),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'শুরুর সময়:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
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
                              setStateDialog(() => startDate = pickedDate);
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (pickedTime != null) {
                              setStateDialog(() => startTime = pickedTime);
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
                  const SizedBox(height: 16),
                  const Text(
                    'শেষের সময়:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
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
                              setStateDialog(() => endDate = pickedDate);
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (pickedTime != null) {
                              setStateDialog(() => endTime = pickedTime);
                            }
                          },
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(
                            endTime == null
                                ? 'সময় বাছুন'
                                : endTime!.format(context),
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
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (startDate == null ||
                  startTime == null ||
                  endDate == null ||
                  endTime == null) {
                Get.snackbar(
                  "সতর্কতা",
                  "দয়া করে শুরু এবং শেষের উভয় তারিখ ও সময় সিলেক্ট করুন।",
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }

              DateTime startDateTime = DateTime(
                startDate!.year,
                startDate!.month,
                startDate!.day,
                startTime!.hour,
                startTime!.minute,
              );

              DateTime endDateTime = DateTime(
                endDate!.year,
                endDate!.month,
                endDate!.day,
                endTime!.hour,
                endTime!.minute,
              );

              if (endDateTime.isBefore(startDateTime)) {
                Get.snackbar(
                  "ত্রুটি",
                  "শেষের সময় শুরুর সময়ের আগে হতে পারে না।",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              }

              try {
                await supabase
                    .from('exam_schedules')
                    .update({
                      'start_time': startDateTime.toIso8601String(),
                      'end_time': endDateTime.toIso8601String(),
                      'is_active': true,
                    })
                    .eq('academy_id', widget.academyId)
                    .eq('class_name', selectedClass!)
                    .eq('subject_name', selectedSubject!)
                    .eq('exam_title', testTitle);

                Get.back();
                Get.snackbar(
                  "সফল",
                  "পরীক্ষার সময় সফলভাবে নির্ধারণ করা হয়েছে।",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
                _loadModelTests();
              } catch (e) {
                debugPrint("Error saving exam schedule: $e");
                Get.snackbar("ত্রুটি", "সময় সংরক্ষণ করতে সমস্যা হয়েছে।");
              }
            },
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelExam(String testTitle) async {
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
          await supabase
              .from('exam_schedules')
              .update({'is_active': false})
              .eq('academy_id', widget.academyId)
              .eq('class_name', selectedClass!)
              .eq('subject_name', selectedSubject!)
              .eq('exam_title', testTitle);

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'মডেল টেস্ট ও খাতা মূল্যায়ন',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedSubject,
                              isExpanded: true,
                              hint: const Text(
                                "বিষয় সিলেক্ট করুন",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
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
                    padding: const EdgeInsets.all(16.0),
                    child: (selectedClass == null || selectedSubject == null)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 56,
                                  color: Colors.indigo.shade200,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'দয়া করে ওপর থেকে ক্লাস এবং বিষয় সিলেক্ট করুন',
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
                                      '$selectedClass - $selectedSubject',
                                      style: TextStyle(
                                        fontSize: 15,
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
                                      'মোট মডেল টেস্ট: ${modelTests.length}',
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
                                child: isLoadingTests || isLoadingSubjects
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : ListView.builder(
                                        // এখানে index 0 এ "সকল প্রশ্ন দেখুন" কার্ড এবং বাকিগুলোতে মডেল টেস্টগুলো দেখানো হচ্ছে
                                        itemCount: modelTests.length + 1,
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            return Card(
                                              elevation: 2,
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              color: Colors.indigo.shade50,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                side: BorderSide(
                                                  color: Colors.indigo.shade200,
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
                                                    Text(
                                                      '📚 $selectedSubject - সকল প্রশ্ন',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                        color: Colors
                                                            .indigo
                                                            .shade900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'এই বিষয়ের মোট প্রশ্ন: $totalSubjectQuestions টি',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors
                                                            .indigo
                                                            .shade700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        ElevatedButton(
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
                                                                    6,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 0,
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
                                                            'সকল প্রশ্ন দেখুন',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }

                                          var test = modelTests[index - 1];
                                          String testTitle = test['exam_title'];
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
                                            DateTime startDt = DateTime.parse(
                                              startTimeStr,
                                            );
                                            DateTime endDt = DateTime.parse(
                                              endTimeStr,
                                            );
                                            formattedTimeText =
                                                'শুরু: ${DateFormat('dd MMM, hh:mm a').format(startDt)}\nশেষ: ${DateFormat('dd MMM, hh:mm a').format(endDt)}';
                                          }

                                          int selectedBtnIndex =
                                              _selectedButtonIndices[testTitle] ??
                                              -1;

                                          return Card(
                                            elevation: 1,
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              side: BorderSide(
                                                color: Colors.grey.shade200,
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
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          testTitle,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                              ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? Colors
                                                                    .green
                                                                    .shade100
                                                              : Colors
                                                                    .red
                                                                    .shade100,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          isActive
                                                              ? 'Active'
                                                              : 'টাইম শেষ / ডিঅ্যাক্টিভ',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: isActive
                                                                ? Colors
                                                                      .green
                                                                      .shade900
                                                                : Colors
                                                                      .red
                                                                      .shade900,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'প্রশ্ন সংখ্যা: $questionCount টি',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: isActive
                                                          ? Colors.green.shade50
                                                          : Colors
                                                                .orange
                                                                .shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isActive
                                                            ? Colors
                                                                  .green
                                                                  .shade200
                                                            : Colors
                                                                  .orange
                                                                  .shade200,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.schedule,
                                                          size: 16,
                                                          color: isActive
                                                              ? Colors
                                                                    .green
                                                                    .shade700
                                                              : Colors
                                                                    .orange
                                                                    .shade700,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            formattedTimeText,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: isActive
                                                                  ? Colors
                                                                        .green
                                                                        .shade900
                                                                  : Colors
                                                                        .orange
                                                                        .shade900,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      if (isActive)
                                                        OutlinedButton(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor:
                                                                Colors.red,
                                                            side:
                                                                const BorderSide(
                                                                  color: Colors
                                                                      .red,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 0,
                                                                ),
                                                          ),
                                                          onPressed: () {
                                                            _cancelExam(
                                                              testTitle,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'ক্যান্সেল',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      if (isActive)
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              selectedBtnIndex ==
                                                                  1
                                                              ? Colors
                                                                    .green
                                                                    .shade700
                                                              : Colors
                                                                    .indigo
                                                                    .shade800,
                                                          foregroundColor:
                                                              Colors.white,
                                                          elevation: 0,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                          ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 0,
                                                              ),
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _selectedButtonIndices[testTitle] =
                                                                1;
                                                          });
                                                          _setExamSchedule(
                                                            testTitle,
                                                          );
                                                        },
                                                        child: const Text(
                                                          'পরীক্ষা শুরু',
                                                          style: TextStyle(
                                                            fontSize: 12,
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
      floatingActionButton: (selectedClass == null || selectedSubject == null)
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'createTestBtn',
                  onPressed: () {
                    Get.to(
                      () => CreateCustomModelTestView(
                        academyId: widget.academyId,
                        className: selectedClass!,
                        subjectName: selectedSubject!,
                        totalSubjectQuestions: totalSubjectQuestions,
                      ),
                    )?.then((_) {
                      _loadModelTests();
                    });
                  },
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
                FloatingActionButton.extended(
                  heroTag: 'createQuestionBtn',
                  onPressed: () {
                    Get.to(
                      () => CreateTestView(
                        academyId: widget.academyId,
                        className: selectedClass!,
                        subjectName: selectedSubject!,
                      ),
                    )?.then((_) {
                      _loadModelTests();
                    });
                  },
                  backgroundColor: Colors.indigo.shade800,
                  elevation: 2,
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
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
            ),
    );
  }
}
