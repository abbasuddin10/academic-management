import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;

  /// Called after a successful save so the caller can refresh immediately.
  final VoidCallback? onSaved;
  final String? currentUserId;
  final String? currentUserName;

  const CreateTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
    this.onSaved,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<CreateTestView> createState() => _CreateTestViewState();
}

class _CreateTestViewState extends State<CreateTestView> {
  final SupabaseClient supabase = Supabase.instance.client;
  final _repository = ModelTestRepository();
  final _formKey = GlobalKey<FormState>();

  // কন্ট্রোলারসমূহ
  final TextEditingController questionController = TextEditingController();
  final TextEditingController customChapterController =
      TextEditingController(); // নতুন অধ্যায় লেখার জন্য
  final TextEditingController optionAController = TextEditingController();
  final TextEditingController optionBController = TextEditingController();
  final TextEditingController optionCController = TextEditingController();
  final TextEditingController optionDController = TextEditingController();
  final TextEditingController explanationController = TextEditingController();

  List<String> existingChapters = []; // সুপাবেস থেকে আসা অধ্যায়ের লিস্ট
  String? selectedChapter; // ড্রপডাউনে সিলেক্ট করা অধ্যায়
  bool isLoadingChapters = true;
  bool isSaving = false;
  String? correctOption = 'A';

  @override
  void initState() {
    super.initState();
    _fetchExistingChapters();
  }

  @override
  void dispose() {
    questionController.dispose();
    customChapterController.dispose();
    optionAController.dispose();
    optionBController.dispose();
    optionCController.dispose();
    optionDController.dispose();
    explanationController.dispose();
    super.dispose();
  }

  // ১. সুপাবেস থেকে নির্দিষ্ট প্রতিষ্ঠান ও বিষয়ের ইউনিক অধ্যায়গুলো ফেচ করা
  Future<void> _fetchExistingChapters() async {
    try {
      final response = await supabase
          .from('academy_questions')
          .select('chapter_name')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName);

      Set<String> chapters = {};
      for (var item in (response as List)) {
        String? chapter = item['chapter_name']?.toString().trim();
        if (chapter != null && chapter.isNotEmpty) {
          chapters.add(chapter);
        }
      }

      setState(() {
        existingChapters = chapters.toList();
        existingChapters.sort();
        isLoadingChapters = false;
      });
    } catch (e) {
      debugPrint("Error loading chapters: $e");
      setState(() => isLoadingChapters = false);
    }
  }

  String generateHash(String text) {
    var bytes = utf8.encode(text.trim().toLowerCase());
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> handleSaveQuestion() async {
    final snackInk = AppTheme.inkOf(context);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    String questionText = questionController.text.trim();
    final options = [
      optionAController.text.trim(),
      optionBController.text.trim(),
      optionCController.text.trim(),
      optionDController.text.trim(),
    ];
    final normalized = options.map((item) => item.toLowerCase()).toList();
    if (normalized.toSet().length != normalized.length) {
      Get.snackbar(
        'সতর্কতা',
        'একই অপশন একাধিকবার দেওয়া যাবে না।',
        backgroundColor: Colors.orangeAccent,
        colorText: snackInk,
      );
      return;
    }
    if (correctOption == null ||
        !['A', 'B', 'C', 'D'].contains(correctOption!.trim().toUpperCase())) {
      Get.snackbar(
        'সতর্কতা',
        'সঠিক উত্তরের অপশন নির্বাচন করুন।',
        backgroundColor: Colors.orangeAccent,
        colorText: snackInk,
      );
      return;
    }
    // question_hash is also enforced by the database trigger in migration 0007.
    String newHash = generateHash(questionText);

    // অধ্যায়ের নাম নির্ধারণ (ড্রপডাউন থেকে সিলেক্ট করা অথবা নতুন লেখা)
    String chapterName = selectedChapter ?? customChapterController.text.trim();
    if (chapterName.isEmpty) {
      chapterName = "সম্পূর্ণ বই";
    }

    setState(() => isSaving = true);

    try {
      // ডুপ্লিকেট চেক (limit(1) — maybeSingle() throws on legacy duplicates).
      final exists = await _repository.questionExists(
        academyId: widget.academyId,
        className: widget.className,
        subjectName: widget.subjectName,
        questionHash: newHash,
      );
      if (exists) {
        Get.snackbar(
          "সতর্কতা: ডুপ্লিকেট প্রশ্ন!",
          "এই প্রশ্নটি ইতিমধ্যে এই ক্লাস ও বিষয়ে সংরক্ষিত রয়েছে।",
          backgroundColor: Colors.orangeAccent,
          colorText: snackInk,
        );
        return;
      }

      // RPC-এর মাধ্যমে সংরক্ষণ: লিগ্যাসি NOT NULL কলাম / RLS সমস্যা এখানে
      // সার্ভারেই সমাধান হয়। RPC না থাকলে repository স্বয়ংক্রিয়ভাবে fallback
      // করে সরাসরি insert এ।
      await _repository.saveQuestion(
        academyId: widget.academyId,
        className: widget.className,
        subjectName: widget.subjectName,
        chapterName: chapterName,
        questionText: questionText,
        optionA: options[0],
        optionB: options[1],
        optionC: options[2],
        optionD: options[3],
        correctOption: correctOption!.trim().toUpperCase(),
        explanation: explanationController.text.trim(),
        questionHash: newHash,
      );

      // ফলাফল নিশ্চিত হওয়ার পরেই সফল বার্তা + তাৎক্ষণিক রিফ্রেশ।
      widget.onSaved?.call();
      Get.snackbar(
        "সফল",
        "প্রশ্নটি সফলভাবে সংরক্ষিত হয়েছে! আরেকটি প্রশ্ন যোগ করতে পারেন।",
        backgroundColor: Colors.teal,
        colorText: Colors.white,
      );

      // ফর্ম রিসেট করা
      questionController.clear();
      customChapterController.clear();
      optionAController.clear();
      optionBController.clear();
      optionCController.clear();
      optionDController.clear();
      explanationController.clear();
      setState(() {
        selectedChapter = null;
        correctOption = 'A';
      });

      // নতুন অধ্যায় যুক্ত হলে লিস্ট রিফ্রেশ করা
      _fetchExistingChapters();
    } catch (e) {
      debugPrint("Error saving question: $e");
      final message = ModelTestRepository.friendlyError(e);
      Get.snackbar(
        "প্রশ্ন সংরক্ষণ ব্যর্থ",
        message.replaceFirst('DUPLICATE:', '').trim(),
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.className} | বিষয়: ${widget.subjectName}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // শিক্ষক ইনফো কার্ড সম্পূর্ণ রিমুভ করা হয়েছে

              // অধ্যায় নির্বাচন ড্রপডাউন বা নতুন লেখার অপশন
              Text(
                'অধ্যায় সিলেক্ট করুন অথবা নতুন লিখুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.inkOf(context),
                ),
              ),
              SizedBox(height: 6),
              isLoadingChapters
                  ? Center(child: LinearProgressIndicator())
                  : Column(
                      children: [
                        // ১. বিদ্যমান অধ্যায়ের ড্রপডাউন
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.borderOf(context),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            color: AppTheme.surfaceOf(context),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedChapter,
                              isExpanded: true,
                              hint: Text(
                                "আগের অধ্যায়গুলোর তালিকা থেকে বেছে নিন (ঐচ্ছিক)",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedOf(context),
                                ),
                              ),
                              items: existingChapters.map((String chapter) {
                                return DropdownMenuItem<String>(
                                  value: chapter,
                                  child: Text(
                                    chapter,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  selectedChapter = newValue;
                                  if (newValue != null) {
                                    customChapterController
                                        .clear(); // ড্রপডাউন থেকে সিলেক্ট করলে টেক্সটফিল্ড খালি হবে
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ২. নতুন অধ্যায় লেখার টেক্সটফিল্ড (যদি তালিকায় না থাকে)
                        TextFormField(
                          controller: customChapterController,
                          decoration: InputDecoration(
                            hintText:
                                'অথবা নতুন অধ্যায়ের নাম লিখুন (যেমন: ৩য় অধ্যায়)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            prefixIcon: const Icon(
                              Icons.bookmark_border,
                              color: Colors.indigo,
                              size: 20,
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              setState(() {
                                selectedChapter =
                                    null; // নতুন কিছু লিখলে ড্রপডাউন সিলেকশন রিসেট হবে
                              });
                            }
                          },
                        ),
                      ],
                    ),
              SizedBox(height: 16),

              // প্রশ্ন লেখার বক্স
              Text(
                'প্রশ্ন লিখুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.inkOf(context),
                ),
              ),
              SizedBox(height: 6),
              TextFormField(
                controller: questionController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'এখানে আপনার মূল প্রশ্নটি লিখুন...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppTheme.tileInkOf(context, Colors.indigo),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'দয়া করে প্রশ্ন লিখুন'
                    : null,
              ),
              SizedBox(height: 16),

              // অপশনসমূহ
              Text(
                'অপশনসমূহ দিন এবং সঠিক উত্তর সিলেক্ট করুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.inkOf(context),
                ),
              ),
              const SizedBox(height: 8),

              _buildOptionField(
                'ক',
                'অপশন ক (Option A)',
                optionAController,
                'A',
              ),
              const SizedBox(height: 10),
              _buildOptionField(
                'খ',
                'অপশন খ (Option B)',
                optionBController,
                'B',
              ),
              SizedBox(height: 10),
              _buildOptionField(
                'গ',
                'অপশন গ (Option C)',
                optionCController,
                'C',
              ),
              SizedBox(height: 10),
              _buildOptionField(
                'ঘ',
                'অপশন ঘ (Option D)',
                optionDController,
                'D',
              ),

              SizedBox(height: 16),

              // উত্তর ব্যাখ্যা
              Text(
                'ব্যাখ্যা (যদি থাকে - ঐচ্ছিক):',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.inkOf(context),
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: explanationController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'সঠিক উত্তরের ছোট ব্যাখ্যা বা নোট দিন...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              SizedBox(height: 24),

              // সেইভ বাটন
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  onPressed: isSaving ? null : handleSaveQuestion,
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
                          'সুপাবেসে প্রশ্ন সেভ করুন',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionField(
    String label,
    String hint,
    TextEditingController controller,
    String optionKey,
  ) {
    bool isSelected = correctOption == optionKey;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.tileOf(context, Colors.teal)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.teal : AppTheme.borderOf(context),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Radio<String>(
            value: optionKey,
            groupValue: correctOption,
            activeColor: Colors.teal,
            onChanged: (String? value) {
              setState(() {
                correctOption = value;
              });
            },
          ),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isSelected
                  ? AppTheme.tileInkOf(context, Colors.teal)
                  : AppTheme.mutedOf(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'ফাঁকা রাখা যাবে না'
                  : null,
            ),
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Icon(
                Icons.check_circle,
                color: Colors.teal.shade700,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
