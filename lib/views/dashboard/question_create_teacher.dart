import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String subjectName;

  const CreateTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.subjectName,
  });

  @override
  State<CreateTestView> createState() => _CreateTestViewState();
}

class _CreateTestViewState extends State<CreateTestView> {
  final SupabaseClient supabase = Supabase.instance.client;
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
      if (response != null) {
        for (var item in (response as List)) {
          String? chapter = item['chapter_name']?.toString().trim();
          if (chapter != null && chapter.isNotEmpty) {
            chapters.add(chapter);
          }
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    String questionText = questionController.text.trim();
    String newHash = generateHash(questionText);

    // অধ্যায়ের নাম নির্ধারণ (ড্রপডাউন থেকে সিলেক্ট করা অথবা নতুন লেখা)
    String chapterName = selectedChapter ?? customChapterController.text.trim();
    if (chapterName.isEmpty) {
      chapterName = "সম্পূর্ণ বই";
    }

    setState(() => isSaving = true);

    try {
      // ২. ডুপ্লিকেট চেক
      final existingCheck = await supabase
          .from('academy_questions')
          .select('id')
          .eq('academy_id', widget.academyId)
          .eq('class_name', widget.className)
          .eq('subject_name', widget.subjectName)
          .eq('question_hash', newHash)
          .maybeSingle();

      if (existingCheck != null) {
        Get.snackbar(
          "সতর্কতা: ডুপ্লিকেট প্রশ্ন!",
          "এই প্রশ্নটি ইতিমধ্যে এই ক্লাস ও বিষয়ে সংরক্ষিত রয়েছে।",
          backgroundColor: Colors.orangeAccent,
          colorText: Colors.black,
        );
        setState(() => isSaving = false);
        return;
      }

      // ৩. সুপাবেসে ডেটা ইনসার্ট করা (শিক্ষক সম্পর্কিত ফিল্ড বাদ দেওয়া হয়েছে)
      await supabase.from('academy_questions').insert({
        'academy_id': widget.academyId,
        'class_name': widget.className,
        'subject_name': widget.subjectName,
        'chapter_name': chapterName,
        'question_text': questionText,
        'option_a': optionAController.text.trim(),
        'option_b': optionBController.text.trim(),
        'option_c': optionCController.text.trim(),
        'option_d': optionDController.text.trim(),
        'correct_option': correctOption,
        'explanation': explanationController.text.trim(),
        'question_hash': newHash,
      });

      Get.snackbar(
        "সফল",
        "প্রশ্নটি সফলভাবে সংরক্ষিত হয়েছে!",
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
      Get.snackbar(
        "ত্রুটি",
        "প্রশ্ন সেভ করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.className} | বিষয়: ${widget.subjectName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // শিক্ষক ইনফো কার্ড সম্পূর্ণ রিমুভ করা হয়েছে

              // অধ্যায় নির্বাচন ড্রপডাউন বা নতুন লেখার অপশন
              const Text(
                'অধ্যায় সিলেক্ট করুন অথবা নতুন লিখুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              isLoadingChapters
                  ? const Center(child: LinearProgressIndicator())
                  : Column(
                      children: [
                        // ১. বিদ্যমান অধ্যায়ের ড্রপডাউন
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedChapter,
                              isExpanded: true,
                              hint: const Text(
                                "আগের অধ্যায়গুলোর তালিকা থেকে বেছে নিন (ঐচ্ছিক)",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
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
              const SizedBox(height: 16),

              // প্রশ্ন লেখার বক্স
              const Text(
                'প্রশ্ন লিখুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
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
                      color: Colors.indigo.shade800,
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
              const SizedBox(height: 16),

              // অপশনসমূহ
              const Text(
                'অপশনসমূহ দিন এবং সঠিক উত্তর সিলেক্ট করুন:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
              const SizedBox(height: 10),
              _buildOptionField(
                'গ',
                'অপশন গ (Option C)',
                optionCController,
                'C',
              ),
              const SizedBox(height: 10),
              _buildOptionField(
                'ঘ',
                'অপশন ঘ (Option D)',
                optionDController,
                'D',
              ),

              const SizedBox(height: 16),

              // উত্তর ব্যাখ্যা
              const Text(
                'ব্যাখ্যা (যদি থাকে - ঐচ্ছিক):',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
              const SizedBox(height: 24),

              // সেইভ বাটন
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade800,
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
                      : const Text(
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
        color: isSelected ? Colors.teal.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.teal : Colors.grey.shade300,
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
              color: isSelected ? Colors.teal.shade800 : Colors.black54,
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
