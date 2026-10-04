import 'dart:io';
import 'dart:typed_data';
import 'package:academy_management/views/dashboard/question_paper_download_admin.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; // লোকাল ফাইল বা পিডিএফ সিলেক্ট করার জন্য
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart'; // তারিখ ও সময় ফরম্যাট করার জন্য
import 'package:open_filex/open_filex.dart';

// ১. মূল পেইজ: পরীক্ষার নামগুলোর কার্ড দেখাবে
// ১. মূল পেইজ: পরীক্ষার নামগুলোর কার্ড দেখাবে
class QuestionCreateView extends StatefulWidget {
  final String academyId;
  final String currentUserId;
  final String currentUserName;
  final String userRole; // সুপার এডমিন বা অন্য রোল চেক করার জন্য যুক্ত করা হলো

  const QuestionCreateView({
    super.key,
    required this.academyId,
    required this.currentUserId,
    required this.currentUserName,
    required this.userRole, // রিকোয়ার্ড হিসেবে রাখা হলো
  });

  @override
  State<QuestionCreateView> createState() => _QuestionCreateViewState();
}

class _QuestionCreateViewState extends State<QuestionCreateView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _examTitlesList = [];

  @override
  void initState() {
    super.initState();
    _fetchExamTitles();
  }

  Future<void> _fetchExamTitles() async {
    try {
      final response = await supabase
          .from('exam_titles')
          .select('*')
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      if (response != null && mounted) {
        setState(() {
          _examTitlesList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('প্রশ্নপত্র তৈরি - পরীক্ষা নির্বাচন'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _examTitlesList.isEmpty
          ? const Center(
              child: Text(
                'এই প্রতিষ্ঠানে কোনো পরীক্ষার নাম যুক্ত করা হয়নি!',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView.builder(
                itemCount: _examTitlesList.length,
                itemBuilder: (context, index) {
                  final exam = _examTitlesList[index];
                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple.shade50,
                            child: const Icon(
                              Icons.assignment_outlined,
                              color: Colors.deepPurple,
                            ),
                          ),
                          title: Text(
                            exam['exam_title'] ?? 'নামহীন পরীক্ষা',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            'ক্লাস নির্বাচন করতে ক্লিক করুন',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.deepPurple,
                          ),
                          onTap: () {
                            // সঠিক আইডি সহ মানগুলো এখানে পাস করা হলো
                            Get.to(
                              () => ClassSelectView(
                                academyId: widget.academyId,
                                examTitleId: exam['id']?.toString() ?? '',
                                examTitle: exam['exam_title'] ?? '',
                                currentUserId: widget.currentUserId,
                                currentUserName: widget.currentUserName,
                              ),
                            );
                          },
                        ),

                        // যদি ইউজার সুপার এডমিন হয়, তবেই এই এক্সট্রা বাটনটি কার্ডের নিচে দেখাবে
                        if (widget.userRole == 'super_admin') ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () {
                                  // **এখানে নতুন পেইজে রিডাইরেক্ট করার কোড যুক্ত করা হলো**
                                  Get.to(
                                    () => QuestionPaperDownloadAdmin(
                                      academyId: widget.academyId,
                                      examTitleId: exam['id']?.toString() ?? '',
                                      examTitle: exam['exam_title'] ?? '',
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  size: 16,
                                ),
                                label: const Text(
                                  'সকল প্রশ্নপত্র ডাউনলোড করতে ক্লিক করুন',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ২. দ্বিতীয় পেইজ: ক্লাস সিলেক্ট করার ভিউ
class ClassSelectView extends StatefulWidget {
  final String academyId;
  final String examTitleId;
  final String examTitle;
  final String currentUserId; // লগইন করা ইউজারের ইউনিক আইডি
  final String currentUserName; // লগইন করা ইউজারের নাম

  const ClassSelectView({
    super.key,
    required this.academyId,
    required this.examTitleId,
    required this.examTitle,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  State<ClassSelectView> createState() => _ClassSelectViewState();
}

class _ClassSelectViewState extends State<ClassSelectView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _classesList = [];

  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  Future<void> _fetchClasses() async {
    try {
      final response = await supabase
          .from('classes')
          .select('*')
          .eq('academy_id', widget.academyId)
          .order('class_order', ascending: true);

      if (response != null && mounted) {
        setState(() {
          _classesList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ফাইল সিলেক্ট করে Supabase-এর 'exam_files' টেবিলে সঠিক ইনফোসহ সেভ করার ফাংশন
  // ফাইল সুপাবেস স্টোরেজে আপলোড করে সঠিক ইউআরএল সহ 'exam_files' টেবিলে সেভ করার ফাংশন
  Future<void> _pickFileAndSaveToSupabase(
    String className,
    String subjectName,
  ) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);

      // ফাইলের আসল নাম বা বাংলায় নাম বাদ দিয়ে শুধুমাত্র এক্সটেনশন নিয়ে নিরাপদ নাম তৈরি করা হলো
      String fileExtension = result.files.single.extension ?? 'pdf';
      String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_file.$fileExtension';

      try {
        // লোডিং ডায়ালগ দেখানো
        Get.dialog(
          const Center(child: CircularProgressIndicator()),
          barrierDismissible: false,
        );

        // ১. প্রথমে সুপাবেস স্টোরেজের 'exam_files' বাক্যে (Bucket) ফাইল আপলোড করুন
        await supabase.storage.from('exam_files').upload(fileName, file);

        // ২. আপলোড করা ফাইলের পাবলিক লিংক বা ইউআরএল সংগ্রহ করুন
        final String fileUrl = supabase.storage
            .from('exam_files')
            .getPublicUrl(fileName);

        // ৩. সুপাবেসের ডাটাবেজ টেবিলে লোকাল পাথের বদলে এই পাবলিক ইউআরএল (fileUrl) সেভ করুন
        await supabase.from('exam_files').insert({
          'academy_id': widget.academyId,
          'exam_title_id': widget.examTitleId.isNotEmpty
              ? widget.examTitleId
              : null,
          'exam_title': widget.examTitle,
          'class_name': className,
          'subject_name': subjectName,
          'file_url': fileUrl,
          'uploaded_by': widget.currentUserId,
          'uploader_name': widget.currentUserName,
        });

        Get.back(); // লোডিং বন্ধ করা

        Get.snackbar(
          'সফলভাবে সংরক্ষিত',
          'বিষয়: $subjectName এবং ফাইলটি সফলভাবে সুপাবেস ক্লাউডে সেভ হয়েছে!',
          backgroundColor: Colors.teal,
          colorText: Colors.white,
        );
      } catch (e) {
        Get.back();
        Get.snackbar(
          'ত্রুটি',
          'ডেটা বা ফাইল সেভ করতে সমস্যা হয়েছে: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  // ভিউ আইকনে ক্লিক করলে শুধুমাত্র নির্দিষ্ট ইউজারের (যিনি আপলোড করেছেন) ফাইলগুলো দেখানোর ফাংশন
  Future<void> _showUploadedFilesInfo() async {
    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      // নির্দিষ্ট একাডেমি, পরীক্ষা এবং নির্দিষ্ট ইউজারের আপলোড করা ফাইলগুলো ফেচ করা
      final response = await supabase
          .from('exam_files')
          .select('*')
          .eq('academy_id', widget.academyId) // ১. নির্দিষ্ট প্রতিষ্ঠান
          .eq('exam_title', widget.examTitle) // ২. নির্দিষ্ট পরীক্ষা
          .eq(
            'uploaded_by',
            widget.currentUserId,
          ); // ৩. শুধুমাত্র নির্দিষ্ট ইউজার (নিজের ফাইল) // শুধুমাত্র নির্দিষ্ট ইউজারের ফাইল ফিল্টার করা

      Get.back(); // লোডিং বন্ধ

      if (response != null) {
        List<Map<String, dynamic>> filesList = List<Map<String, dynamic>>.from(
          response,
        );

        Get.defaultDialog(
          title: 'আপনার আপলোড করা ফাইলসমূহ',
          titleStyle: const TextStyle(
            color: Colors.deepPurple,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: filesList.isEmpty
                ? const Center(
                    child: Text(
                      'এই পরীক্ষার জন্য আপনার কোনো ফাইল আপলোড করা নেই।',
                    ),
                  )
                : ListView.builder(
                    itemCount: filesList.length,
                    itemBuilder: (context, index) {
                      final item = filesList[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 1,
                        child: ListTile(
                          title: Text(
                            'বিষয়: ${item['subject_name'] ?? 'নেই'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'শ্রেণি: ${item['class_name']}\nআপলোডকারী: ${item['uploader_name'] ?? 'অজানা'}\nসময়: ${item['created_at']?.toString().substring(0, 16) ?? ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
          textConfirm: 'বন্ধ করুন',
          confirmTextColor: Colors.white,
          buttonColor: Colors.deepPurple,
          onConfirm: () => Get.back(),
        );
      }
    } catch (e) {
      Get.back();
      Get.snackbar(
        'ত্রুটি',
        'তথ্য লোড করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.examTitle),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: 'ভিউ',
            onPressed: () {
              // ডায়ালগের পরিবর্তে এখন সরাসরি আলাদা পেইজে রিডায়রেক্ট হবে
              Get.to(
                () => UploadedFilesView(
                  academyId: widget.academyId,
                  examTitle: widget.examTitle,
                  currentUserId: widget.currentUserId,
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classesList.isEmpty
          ? const Center(
              child: Text(
                'এই প্রতিষ্ঠানে কোনো ক্লাস যুক্ত করা হয়নি!',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'একটি শ্রেণি নির্বাচন করুন:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.55,
                          ),
                      itemCount: _classesList.length,
                      itemBuilder: (context, index) {
                        final classItem = _classesList[index];
                        final className = classItem['class_name'] ?? 'ক্লাস';

                        return InkWell(
                          onTap: () {
                            Get.to(
                              () => SubjectQuestionView(
                                academyId: widget.academyId,
                                examTitle: widget.examTitle,
                                className: className,
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade200,
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                ),
                              ],
                              border: Border.all(
                                color: Colors.deepPurple.shade100,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          Colors.deepPurple.shade50,
                                      radius: 15,
                                      child: const Icon(
                                        Icons.class_,
                                        color: Colors.deepPurple,
                                        size: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        className,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 13,
                                      color: Colors.deepPurple,
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6.0,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.deepPurple.shade50,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 29,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.deepPurple.shade50,
                                      foregroundColor: Colors.deepPurple,
                                      elevation: 0,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    onPressed: () {
                                      // বিষয়ের নাম ইনপুট নেওয়ার জন্য কন্ট্রোলার
                                      final TextEditingController
                                      subjectController =
                                          TextEditingController();

                                      // পপ-আপ ডায়ালগ
                                      Get.defaultDialog(
                                        title: 'প্রশ্ন জমা করুন',
                                        titleStyle: const TextStyle(
                                          color: Colors.deepPurple,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                        content: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 8),
                                            Text(
                                              'পরীক্ষার নাম: ${widget.examTitle}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'শ্রেণি: $className',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            // বিষয়ের নাম লেখার টেক্সট ফিল্ড (বাধ্যতামূলক)
                                            TextField(
                                              controller: subjectController,
                                              decoration: const InputDecoration(
                                                labelText: 'বিষয়ের নাম লিখুন *',
                                                hintText: 'যেমন: বাংলা / গণিত',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              'লোকাল মেমোরি থেকে প্রশ্নপত্র (PDF/Image) সিলেক্ট করুন:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        textConfirm: 'ফাইল সিলেক্ট ও সাবমিট',
                                        confirmTextColor: Colors.white,
                                        buttonColor: Colors.deepPurple,
                                        onConfirm: () {
                                          String subjectName = subjectController
                                              .text
                                              .trim();

                                          // যদি বিষয়ের নাম ফাঁকা থাকে, তবে অ্যালার্ট দেখাবে এবং আটকে রাখবে
                                          if (subjectName.isEmpty) {
                                            Get.snackbar(
                                              'সতর্কতা',
                                              'দয়া করে প্রথমে বিষয়ের নাম যুক্ত করুন!',
                                              backgroundColor: Colors.red,
                                              colorText: Colors.white,
                                            );
                                            return;
                                          }

                                          Get.back(); // ডায়ালগ বন্ধ করা

                                          // ফাইল সিলেক্ট করে সুপাবেসে সেভ করার ফাংশন কল
                                          _pickFileAndSaveToSupabase(
                                            className,
                                            subjectName,
                                          );
                                        },
                                        textCancel: 'বাতিল',
                                        cancelTextColor: Colors.deepPurple,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.upload_file,
                                      size: 13,
                                    ),
                                    label: const Text(
                                      'প্রশ্ন জমা করুন',
                                      style: TextStyle(fontSize: 13),
                                    ),
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
    );
  }
}

// ৩. তৃতীয় পেইজ: বিষয়, প্রশ্ন ইনপুট
class SubjectQuestionView extends StatefulWidget {
  final String academyId;
  final String examTitle;
  final String className;

  const SubjectQuestionView({
    super.key,
    required this.academyId,
    required this.examTitle,
    required this.className,
  });

  @override
  State<SubjectQuestionView> createState() => _SubjectQuestionViewState();
}

class _SubjectQuestionViewState extends State<SubjectQuestionView> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _fullMarkController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  bool _isExtracting = false;
  File? _pickedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _subjectController.dispose();
    _fullMarkController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (image != null) {
      setState(() {
        _pickedImage = File(image.path);
      });
    }
  }

  Future<void> _extractAndProceed() async {
    if (_pickedImage == null) {
      Get.snackbar(
        "ত্রুটি",
        "প্রথমে ছবি সিলেক্ট করুন",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (_subjectController.text.trim().isEmpty) {
      Get.snackbar(
        "ত্রুটি",
        "বিষয়ের নাম লিখুন",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isExtracting = true);

    try {
      const apiKey = "";
      final model = GenerativeModel(model: 'gemini-3.6-flash', apiKey: apiKey);
      final imageBytes = await _pickedImage!.readAsBytes();

      final response = await model.generateContent([
        Content.multi([
          TextPart(
            "Extract all text from this exam paper image with 100% precision, preserving exact Bangla and English text formatting.",
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]);

      setState(() => _isExtracting = false);

      Get.to(
        () => QuestionEditorView(
          academyId: widget.academyId,
          examTitle: widget.examTitle,
          className: widget.className,
          subjectName: _subjectController.text.trim(),
          fullMark: _fullMarkController.text.trim(),
          examTime: _timeController.text.trim(),
          initialQuestionText: response.text ?? '',
        ),
      );
    } catch (e) {
      setState(() => _isExtracting = false);
      Get.snackbar(
        "ত্রুটি",
        "এক্সট্রাক্ট করা যায়নি: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _proceedManualTyping() {
    if (_subjectController.text.trim().isEmpty) {
      Get.snackbar(
        "ত্রুটি",
        "বিষয়ের নাম লিখুন",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    Get.to(
      () => QuestionEditorView(
        academyId: widget.academyId,
        examTitle: widget.examTitle,
        className: widget.className,
        subjectName: _subjectController.text.trim(),
        fullMark: _fullMarkController.text.trim(),
        examTime: _timeController.text.trim(),
        initialQuestionText: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.className} - প্রশ্ন তৈরি'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'বিষয়ের নাম',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fullMarkController,
                    decoration: const InputDecoration(
                      labelText: 'পূর্ণমান',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _timeController,
                    decoration: const InputDecoration(
                      labelText: 'সময়',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('ক্যামেরা'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('গ্যালারি'),
                  ),
                ),
              ],
            ),
            if (_pickedImage != null) ...[
              const SizedBox(height: 12),
              Image.file(
                _pickedImage!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isExtracting ? null : _extractAndProceed,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _isExtracting ? 'প্রসেসিং হচ্ছে...' : 'এআই দিয়ে টেক্সট নিন',
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _proceedManualTyping,
              icon: const Icon(Icons.edit_note),
              label: const Text('ম্যানুয়ালী টাইপ করে এগিয়ে যান'),
            ),
          ],
        ),
      ),
    );
  }
}

// সাব-প্রশ্ন মডেল (সাধারণ প্রশ্নের জন্য একাধিক প্রশ্ন যোগ করতে)
class SubQuestionModel {
  TextEditingController descController;
  TextEditingController markController;
  bool isHidden;

  SubQuestionModel({String desc = '', String mark = '', this.isHidden = false})
    : descController = TextEditingController(text: desc),
      markController = TextEditingController(text: mark);
}

// ৪. চতুর্থ পেইজ: ইন্টারঅ্যাক্টিভ টেবিল এবং প্রশ্ন এডিটর
class QuestionItem {
  bool isTable;
  String questionTitle; // উদ্দীপক অথবা টেবিল শিরোনাম
  String questionMark; // টেবিলের মার্কস
  int cols;
  double boxSize;
  bool isHidden;
  List<TextEditingController> cellControllers; // টেবিল ঘরের জন্য
  List<SubQuestionModel> subQuestions; // সাধারণ প্রশ্নের সাব-প্রশ্নগুলোর লিস্ট

  QuestionItem({
    required this.isTable,
    this.questionTitle = '',
    this.questionMark = '',
    this.cols = 8,
    this.boxSize = 70.0,
    this.isHidden = false,
    List<TextEditingController>? controllers,
    List<SubQuestionModel>? subQuestions,
  }) : cellControllers =
           controllers ?? List.generate(cols, (_) => TextEditingController()),
       subQuestions = subQuestions ?? [SubQuestionModel()];
}

class QuestionEditorView extends StatefulWidget {
  final String academyId;
  final String examTitle;
  final String className;
  final String subjectName;
  final String fullMark;
  final String examTime;
  final String initialQuestionText;

  const QuestionEditorView({
    super.key,
    required this.academyId,
    required this.examTitle,
    required this.className,
    required this.subjectName,
    required this.fullMark,
    required this.examTime,
    required this.initialQuestionText,
  });

  @override
  State<QuestionEditorView> createState() => _QuestionEditorViewState();
}

class _QuestionEditorViewState extends State<QuestionEditorView> {
  final List<QuestionItem> _items = [];
  String _academyName = 'প্রতিষ্ঠান';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestionText.isNotEmpty) {
      _items.add(
        QuestionItem(
          isTable: false,
          questionTitle: '',
          subQuestions: [SubQuestionModel(desc: widget.initialQuestionText)],
        ),
      );
    } else {
      _items.add(
        QuestionItem(
          isTable: true,
          questionTitle: '',
          questionMark: '',
          cols: 6,
          boxSize: 70.0,
        ),
      );
    }

    _fetchAcademyName();
  }

  Future<void> _fetchAcademyName() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('academies')
          .select()
          .eq('id', widget.academyId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _academyName =
              response['academy_name'] ?? response['name'] ?? 'প্রতিষ্ঠান';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (var item in _items) {
      for (var c in item.cellControllers) {
        c.dispose();
      }
      for (var sub in item.subQuestions) {
        sub.descController.dispose();
        sub.markController.dispose();
      }
    }
    super.dispose();
  }

  void _addTextQuestion() {
    setState(() {
      _items.add(
        QuestionItem(
          isTable: false,
          questionTitle: '',
          subQuestions: [SubQuestionModel()],
        ),
      );
    });
  }

  void _addTableQuestion() {
    final TextEditingController colController = TextEditingController(
      text: '8',
    );
    double selectedBoxSize = 70.0;

    Get.defaultDialog(
      title: 'ঘরের টেবিল যোগ করুন',
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(
              controller: colController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'মোট কয়টি ঘর লাগবে? (যেমন: ৮)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: selectedBoxSize,
              decoration: const InputDecoration(
                labelText: 'ঘরের সাইজ',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 60.0, child: Text('ছোট (Small)')),
                DropdownMenuItem(value: 70.0, child: Text('মাঝারি (Medium)')),
                DropdownMenuItem(value: 80.0, child: Text('বড় (Large)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  selectedBoxSize = val;
                }
              },
            ),
          ],
        ),
      ),
      textConfirm: 'তৈরি করুন',
      confirmTextColor: Colors.white,
      buttonColor: Colors.deepPurple,
      onConfirm: () {
        int cols = int.tryParse(colController.text) ?? 8;
        Get.back();
        setState(() {
          _items.add(
            QuestionItem(
              isTable: true,
              questionTitle: '',
              questionMark: '',
              cols: cols,
              boxSize: selectedBoxSize,
            ),
          );
        });
      },
    );
  }

  Future<Uint8List> _generatePdfBytes(PdfPageFormat format) async {
    String htmlContentBody = '';

    for (var item in _items) {
      if (!item.isTable) {
        String titleSection = item.questionTitle.isNotEmpty
            ? '<div style="margin-top: 15px; font-weight: normal; font-size: 13pt;">${item.questionTitle}</div>'
            : '';

        String subQuestionsHtml = '';
        for (var sub in item.subQuestions) {
          if (sub.descController.text.isNotEmpty) {
            String sMark = sub.markController.text.isNotEmpty
                ? sub.markController.text
                : '';
            subQuestionsHtml +=
                '''
              <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-top: 8px; margin-left: 20px; font-weight: normal; font-size: 13pt;">
                <div style="flex: 1; padding-right: 15px;">${sub.descController.text}</div>
                <div style="white-space: nowrap;">$sMark</div>
              </div>
            ''';
          }
        }
        htmlContentBody += titleSection + subQuestionsHtml;
      } else {
        String qMark = item.questionMark.isNotEmpty ? item.questionMark : '';
        String titleSection = item.questionTitle.isNotEmpty || qMark.isNotEmpty
            ? '''
              <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-top: 15px; font-weight: normal; font-size: 13pt;">
                <div style="flex: 1; padding-right: 15px;">${item.questionTitle}</div>
                <div style="white-space: nowrap;">$qMark</div>
              </div>
            '''
            : '';

        String tds = '';
        for (var c in item.cellControllers) {
          tds += '<td><span>${c.text}</span></td>';
        }

        htmlContentBody +=
            '''
          $titleSection
          <style>
            .table-${item.hashCode} {
              display: flex;
              flex-wrap: wrap;
              max-width: 100%;
              margin-top: 10px;
            }
            .table-${item.hashCode} td {
              width: ${item.boxSize}px !important;
              height: ${item.boxSize}px !important;
              font-size: ${item.boxSize > 70 ? '16pt' : '13pt'} !important;
              border: 1px solid #000;
              text-align: center;
              vertical-align: middle;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              padding: 0;
              margin: 0;
              box-sizing: border-box;
            }
          </style>
          <table class="letter-box table-${item.hashCode}"><tr>$tds</tr></table>
        ''';
      }
    }

    final htmlContent =
        '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          @page { size: A4; margin: 0.8in; }
          body { font-family: 'SolaimanLipi', 'Arial', sans-serif; font-size: 14pt; color: #000; line-height: 1.5; margin: 0; padding: 0; }
          .header { text-align: center; margin-bottom: 15px; }
          .academy-title { font-size: 20pt; font-weight: normal; margin: 0 0 5px 0; }
          .exam-title { font-size: 16pt; font-weight: normal; margin: 0 0 5px 0; }
          .sub-info { font-size: 13pt; font-weight: normal; margin: 0 0 10px 0; }
          hr { border: none; border-top: 1.5px solid #000; margin: 10px 0 15px 0; }
          
          table.letter-box {
            border-collapse: collapse;
            margin: 0;
            padding: 0;
          }
        </style>
      </head>
      <body>
       <div class="header">
          <div class="academy-title">$_academyName</div>
          <div class="exam-title">${widget.examTitle}</div>
          <div class="sub-info">শ্রেণি : ${widget.className} &nbsp;&nbsp;  &nbsp;&nbsp; বিষয় : ${widget.subjectName}</div>
          <div style="display: flex; justify-content: space-between; font-weight: normal;">
            <span>পূর্ণমান : ${widget.fullMark.isNotEmpty ? widget.fullMark : '100'}</span>
            <span>সময় : ${widget.examTime.isNotEmpty ? widget.examTime : '2 hrs.'}</span>
          </div>
          <hr>
        </div>
        <div>$htmlContentBody</div>
      </body>
      </html>
    ''';
    return await Printing.convertHtml(format: format, html: htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('প্রশ্নপত্র এডিটর'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.print, size: 20),
            label: const Text(
              'প্রিন্ট / পিডিএফ',
              style: TextStyle(fontWeight: FontWeight.normal),
            ),
            onPressed: () async {
              await Printing.layoutPdf(
                onLayout: (format) => _generatePdfBytes(format),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.deepPurple.shade50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 12.0,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addTextQuestion,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('সাধারণ প্রশ্ন'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _addTableQuestion,
                    icon: const Icon(Icons.grid_on),
                    label: const Text('টেবিল প্রশ্ন'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _addTableQuestion,
                    icon: const Icon(Icons.graphic_eq),
                    label: const Text('শুন্যস্থান  যোগ'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 85, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.isTable) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: item.questionTitle,
                                      onChanged: (val) =>
                                          item.questionTitle = val,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 15,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'টেবিলের শিরোনাম (ঐচ্ছিক)',
                                        hintText: 'এখানে শিরোনাম লিখুন...',
                                        border: UnderlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      initialValue: item.questionMark,
                                      onChanged: (val) =>
                                          item.questionMark = val,
                                      keyboardType: TextInputType.text,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 15,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'মার্কস',
                                        hintText: '৫',
                                        border: UnderlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ] else ...[
                              TextFormField(
                                initialValue: item.questionTitle,
                                onChanged: (val) => item.questionTitle = val,
                                style: const TextStyle(
                                  fontWeight: FontWeight.normal,
                                  fontSize: 15,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'উদ্দীপক বা বিবরণ (ঐচ্ছিক)',
                                  hintText: 'এখানে উদ্দীপক লিখুন...',
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                              if (!item.isHidden) ...[
                                const SizedBox(height: 12),
                                ...item.subQuestions.asMap().entries.map((
                                  entry,
                                ) {
                                  int subIdx = entry.key;
                                  SubQuestionModel sub = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 8.0,
                                      left: 16.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: sub.descController,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.normal,
                                              fontSize: 16,
                                            ),
                                            decoration: InputDecoration(
                                              labelText:
                                                  'মূল প্রশ্ন ${subIdx + 1}',
                                              hintText:
                                                  'যেমন: ক) সঠিক উত্তরটি লেখো :',
                                              border:
                                                  const UnderlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 70,
                                          child: TextField(
                                            controller: sub.markController,
                                            keyboardType: TextInputType.text,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.normal,
                                              fontSize: 15,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'মার্কস',
                                              hintText: '৫',
                                              border: UnderlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          tooltip: 'প্রশ্ন ডিলিট',
                                          onPressed: () {
                                            setState(() {
                                              sub.descController.dispose();
                                              sub.markController.dispose();
                                              item.subQuestions.removeAt(
                                                subIdx,
                                              );
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        item.subQuestions.add(
                                          SubQuestionModel(),
                                        );
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.add,
                                      color: Colors.deepPurple,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'আরও একটি মূল প্রশ্ন যোগ করুন',
                                      style: TextStyle(
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],

                            if (!item.isHidden && item.isTable) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4.0,
                                runSpacing: 4.0,
                                children: List.generate(item.cols, (cellIdx) {
                                  return SizedBox(
                                    width: item.boxSize,
                                    height: item.boxSize,
                                    child: TextField(
                                      controller: item.cellControllers[cellIdx],
                                      textAlign: TextAlign.center,
                                      textAlignVertical:
                                          TextAlignVertical.center,
                                      style: TextStyle(
                                        fontSize: item.boxSize > 70 ? 16 : 14,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 0,
                                              horizontal: 0,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                item.isHidden
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey.shade700,
                                size: 20,
                              ),
                              tooltip: item.isHidden
                                  ? 'দেখাচ্ছে'
                                  : 'লুকিয়ে রাখুন',
                              onPressed: () {
                                setState(() {
                                  item.isHidden = !item.isHidden;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 20,
                              ),
                              tooltip: 'ডিলিট করুন',
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// নতুন পেইজ: ইউজারের আপলোড করা ফাইলসমূহ দেখার জন্য

class UploadedFilesView extends StatefulWidget {
  final String academyId;
  final String examTitle;
  final String currentUserId;

  const UploadedFilesView({
    super.key,
    required this.academyId,
    required this.examTitle,
    required this.currentUserId,
  });

  @override
  State<UploadedFilesView> createState() => _UploadedFilesViewState();
}

class _UploadedFilesViewState extends State<UploadedFilesView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _filesList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUploadedFiles();
  }

  // সুপাবেস থেকে ডাটা ফেচ করা
  Future<void> _fetchUploadedFiles() async {
    try {
      final response = await supabase
          .from('exam_files')
          .select('*')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', widget.examTitle)
          .eq('uploaded_by', widget.currentUserId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _filesList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // সুপাবেস এবং লোকাল স্টোরেজ থেকে ফাইল চিরতরে ডিলিট করা
  Future<void> _deleteFileRecord(String id, String fileUrl) async {
    Get.defaultDialog(
      title: 'চিরতরে ডিলিট',
      middleText:
          'আপনি কি নিশ্চিতভাবে এই ফাইলটি সুপাবেস এবং অ্যাপ থেকে চিরতরে মুছে ফেলতে চান?',
      textConfirm: 'হ্যাঁ, ডিলিট',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      textCancel: 'বাতিল',
      onConfirm: () async {
        Get.back(); // ডায়ালগ বন্ধ
        try {
          Get.dialog(
            const Center(child: CircularProgressIndicator()),
            barrierDismissible: false,
          );

          // ১. সুপাবেস স্টোরেজ থেকে ফাইল পাথ বের করে ডিলিট করা
          if (fileUrl.isNotEmpty) {
            Uri uri = Uri.parse(fileUrl);
            // সুপাবেস পাবলিক ইউআরএল থেকে ফাইলের নাম বা পাথ আলাদা করা
            String filePath = uri.pathSegments.last;
            await supabase.storage.from('exam_files').remove([filePath]);
          }

          // ২. সুপাবেস ডাটাবেজ টেবিল থেকে রেকর্ড ডিলিট
          await supabase.from('exam_files').delete().eq('id', id);

          Get.back(); // লোডিং বন্ধ

          // ৩. সাথে সাথে স্টেট আপডেট করে UI থেকে সরিয়ে দেওয়া
          setState(() {
            _filesList.removeWhere((item) => item['id'].toString() == id);
          });

          Get.snackbar(
            'সফল',
            'ফাইলটি সুপাবেস থেকে চিরতরে ডিলিট করা হয়েছে',
            backgroundColor: Colors.teal,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.back();
          Get.snackbar(
            'ত্রুটি',
            'ডিলিট করতে সমস্যা হয়েছে: $e',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // তথ্য বা বিষয়ের নাম আপডেট করা (সুপাবেস এবং অ্যাপে সাথে সাথে দেখাবে)
  void _editFileRecord(Map<String, dynamic> item) {
    final TextEditingController subjectController = TextEditingController(
      text: item['subject_name'],
    );

    Get.defaultDialog(
      title: 'বিষয়ের নাম আপডেট করুন',
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          controller: subjectController,
          decoration: const InputDecoration(
            labelText: 'নতুন বিষয়ের নাম',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      textConfirm: 'সংরক্ষণ',
      confirmTextColor: Colors.white,
      buttonColor: Colors.deepPurple,
      onConfirm: () async {
        String newSubject = subjectController.text.trim();
        if (newSubject.isEmpty) return;

        Get.back();
        try {
          Get.dialog(
            const Center(child: CircularProgressIndicator()),
            barrierDismissible: false,
          );

          // সুপাবেসে আপডেট করা
          await supabase
              .from('exam_files')
              .update({'subject_name': newSubject})
              .eq('id', item['id']);

          Get.back(); // লোডিং বন্ধ

          // সাথে সাথে লোকাল লিস্ট আপডেট করা যাতে পেইজ রিলোড ছাড়াই দেখা যায়
          setState(() {
            final index = _filesList.indexWhere(
              (element) => element['id'] == item['id'],
            );
            if (index != -1) {
              _filesList[index]['subject_name'] = newSubject;
            }
          });

          Get.snackbar(
            'সফল',
            'বিষয়ের নাম সফলভাবে আপডেট হয়েছে',
            backgroundColor: Colors.teal,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.back();
          Get.snackbar(
            'ত্রুটি',
            'আপডেট করতে সমস্যা হয়েছে: $e',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
      textCancel: 'বাতিল',
    );
  }

  // ইউজারের ডিভাইসের লোকাল স্টোরেজে ফাইল ডাউনলোড করার ফাংশন

  Future<void> _downloadFile(String url, String subjectName) async {
    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      // ১. ফাইলের এক্সটেনশন লিংক থেকে বের করা (pdf, jpg, png, docx ইত্যাদি)
      String extension = 'pdf';
      String lowerUrl = url.toLowerCase();
      if (lowerUrl.contains('.jpg') || lowerUrl.contains('.jpeg')) {
        extension = 'jpg';
      } else if (lowerUrl.contains('.png')) {
        extension = 'png';
      } else if (lowerUrl.contains('.doc') || lowerUrl.contains('.docx')) {
        extension = 'docx';
      } else if (lowerUrl.contains('.pdf')) {
        extension = 'pdf';
      }

      // ২. অ্যাপের লোকাল টেম্পোরারি বা এক্সটার্নাল ডিরেক্টরি ব্যবহার করা (যা ১০০% কাজ করে)
      Directory tempDir = await getTemporaryDirectory();
      String cleanSubject = subjectName
          .replaceAll(RegExp(r'[^\w\s]+'), '')
          .trim()
          .replaceAll(' ', '_');
      String fileName =
          '${cleanSubject}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      String savePath = '${tempDir.path}/$fileName';

      // ৩. Dio দিয়ে ফাইল ডাউনলোড করা
      await Dio().download(url, savePath);

      Get.back(); // লোডিং ডায়ালগ বন্ধ

      // ৪. ফাইলটি সফলভাবে ডাউনলোড হওয়ার পর সাথে সাথে ইউজারের সামনে ওপেন বা ভিউ করার অপশন দেওয়া
      final result = await OpenFilex.open(savePath);

      if (result.type != ResultType.done) {
        Get.snackbar(
          'সফল',
          'ফাইল ডাউনলোড হয়েছে কিন্তু ওপেন করা যায়নি: ${result.message}',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'ডাউনলোড সফল',
          'ফাইলটি সফলভাবে ডাউনলোড ও ওপেন হয়েছে!',
          backgroundColor: Colors.teal,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'ত্রুটি',
        'ডাউনলোড করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    }
  }

  // সুপাবেসের সময়কে বাংলাদেশের সময় জোনে (GMT+6) রূপান্তর করার ফাংশন
  String _formatBangladeshTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      DateTime utcDate = DateTime.parse(timestamp).toUtc();
      // বাংলাদেশের জন্য ৬ ঘণ্টা যোগ করা (UTC +6)
      DateTime bdDate = utcDate.add(const Duration(hours: 6));
      return DateFormat('dd MMM yyyy, hh:mm a').format(bdDate);
    } catch (e) {
      return timestamp.substring(0, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('${widget.examTitle} - ফাইলসমূহ'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filesList.isEmpty
          ? const Center(
              child: Text(
                'এই পরীক্ষার জন্য আপনার কোনো ফাইল আপলোড করা নেই।',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchUploadedFiles,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filesList.length,
                itemBuilder: (context, index) {
                  final item = _filesList[index];
                  String fileUrl = item['file_url'] ?? '';
                  String subjectName = item['subject_name'] ?? 'নেই';
                  String formattedTime = _formatBangladeshTime(
                    item['created_at'],
                  );

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade50,
                                child: const Icon(
                                  Icons.insert_drive_file,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'বিষয়: $subjectName',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'শ্রেণি: ${item['class_name']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // এডিট এবং ডিলিট মেনু
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editFileRecord(item);
                                  } else if (value == 'delete') {
                                    _deleteFileRecord(
                                      item['id'].toString(),
                                      fileUrl,
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: Colors.blue,
                                        ),
                                        SizedBox(width: 8),
                                        Text('এডিট করুন'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text('ডিলিট করুন'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'সময়: $formattedTime',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple.shade50,
                                  foregroundColor: Colors.deepPurple,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  if (fileUrl.isNotEmpty) {
                                    _downloadFile(fileUrl, subjectName);
                                  } else {
                                    Get.snackbar(
                                      'ত্রুটি',
                                      'ফাইলের লিংক পাওয়া যায়নি',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text(
                                  'ডাউনলোড করুন',
                                  style: TextStyle(fontSize: 12),
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
    );
  }
}
