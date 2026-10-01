import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

// ১. মূল পেইজ: পরীক্ষার নামগুলোর কার্ড দেখাবে
class QuestionCreateView extends StatefulWidget {
  final String academyId;

  const QuestionCreateView({super.key, required this.academyId});

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
                    child: ListTile(
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
                        Get.to(
                          () => ClassSelectView(
                            academyId: widget.academyId,
                            examTitle: exam['exam_title'],
                          ),
                        );
                      },
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
  final String examTitle;

  const ClassSelectView({
    super.key,
    required this.academyId,
    required this.examTitle,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.examTitle),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
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
                            childAspectRatio: 2.2,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.deepPurple.shade50,
                                  radius: 18,
                                  child: const Icon(
                                    Icons.class_,
                                    color: Colors.deepPurple,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
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
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
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

    // ইউজার যেভাবে সিরিয়াল অনুযায়ী সাজিয়েছেন, ঠিক সেই ক্রমানুসারে (হাইড থাকা বা না থাকা নিরপেক্ষভাবে) লুপ চালিয়ে রেন্ডার করা হচ্ছে
    for (var item in _items) {
      if (!item.isTable) {
        // সাধারণ প্রশ্ন ও সাব-প্রশ্ন রেন্ডারিং
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
        // টেবিল প্রশ্ন রেন্ডারিং
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
                  // এখন প্রথমে "সাধারণ প্রশ্ন যোগ করুন" বাটন রাখা হয়েছে
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
                              // টেবিল প্রশ্ন: শিরোনাম এবং মার্কস ইনপুট
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
                              // সাধারণ প্রশ্ন: উদ্দীপক ইনপুট
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
                                // একাধিক মূল প্রশ্ন ডাইনামিকালি যোগ করার লিস্ট
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

                            // টেবিল ঘর বা বক্সগুলো (যদি টেবিল প্রশ্ন হয়)
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
                      // ভিউ/হাইড এবং ডিলিট আইকনগুলো কার্ডের একদম উপরে ডান কোণায় সেট করা হয়েছে
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
