import 'package:academy_management/views/dashboard/Create_Exam_Routine_Page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';

class ExamRoutineView extends StatefulWidget {
  final String academyId;

  const ExamRoutineView({Key? key, required this.academyId}) : super(key: key);

  @override
  State<ExamRoutineView> createState() => _ExamRoutineViewState();
}

class _ExamRoutineViewState extends State<ExamRoutineView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> examList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchExams();
  }

  // ১. নির্দিষ্ট একাডেমি আইডি অনুযায়ী পরীক্ষার নামগুলো ফেচ করা
  // ১. নির্দিষ্ট একাডেমি আইডি অনুযায়ী পরীক্ষার নামগুলো ফেচ করা
  Future<void> _fetchExams() async {
    try {
      final response = await supabase
          .from('exam_titles')
          .select()
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      // উইজেট স্ক্রিনে সচল (mounted) আছে কিনা তা চেক করা
      if (mounted) {
        if (response != null) {
          setState(() {
            examList = List<Map<String, dynamic>>.from(response);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        Get.snackbar(
          "ত্রুটি",
          "পরীক্ষার তালিকা লোড করতে সমস্যা হয়েছে: $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  // ২. নতুন পরীক্ষা যোগ করার ডায়ালগ
  void _showAddExamDialog() {
    final TextEditingController examTitleController = TextEditingController();

    Get.defaultDialog(
      title: "নতুন পরীক্ষা যোগ করুন",
      titleStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: TextField(
          controller: examTitleController,
          decoration: InputDecoration(
            labelText: 'পরীক্ষার নাম (যেমন: ১ম সাময়িক পরীক্ষা)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ),
      textConfirm: "সেভ করুন",
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        String examTitle = examTitleController.text.trim();
        if (examTitle.isEmpty) {
          Get.snackbar(
            "সতর্কতা",
            "দয়া করে পরীক্ষার নাম লিখুন!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        try {
          await supabase.from('exam_titles').insert({
            'academy_id': widget.academyId,
            'exam_title': examTitle,
          });

          Get.back();
          _fetchExams();
          Get.snackbar(
            "সফল",
            "পরীক্ষার নাম সফলভাবে যোগ করা হয়েছে!",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "সংরক্ষণ করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // ৩. পরীক্ষার নাম এডিট করার ডায়ালগ
  void _showEditExamDialog(String examId, String currentTitle) {
    final TextEditingController examTitleController = TextEditingController(
      text: currentTitle,
    );

    Get.defaultDialog(
      title: "পরীক্ষার নাম পরিবর্তন করুন",
      titleStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: TextField(
          controller: examTitleController,
          decoration: InputDecoration(
            labelText: 'পরীক্ষার নাম',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ),
      textConfirm: "আপডেট করুন",
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        String newTitle = examTitleController.text.trim();
        if (newTitle.isEmpty) {
          Get.snackbar(
            "সতর্কতা",
            "দয়া করে পরীক্ষার নাম লিখুন!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        try {
          // সুপাবেসে exam_titles টেবিল আপডেট করা
          await supabase
              .from('exam_titles')
              .update({'exam_title': newTitle})
              .eq('id', examId);

          // যদি রুটিন টেবিলেও পরীক্ষার নাম সেভ করা থাকে, তবে তা আপডেট করতে পারেন
          await supabase
              .from('exam_routines')
              .update({'exam_title': newTitle})
              .eq('exam_id', examId);

          Get.back();
          _fetchExams();
          Get.snackbar(
            "সফল",
            "পরীক্ষার নাম সফলভাবে আপডেট করা হয়েছে!",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "আপডেট করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // ৪. পরীক্ষা এবং এর অধীনে থাকা রুটিন ডিলিট করার কনফার্মেশন ডায়ালগ
  void _showDeleteConfirmation(String examId, String examTitle) {
    Get.defaultDialog(
      title: "সতর্কতা!",
      titleStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.red,
      ),
      middleText:
          "আপনি কি '$examTitle' ডিলিট করতে চান?\n\nএটি ডিলিট করলে এর অধীনে থাকা সকল রুটিন চিরতরে মুছে যাবে!",
      textConfirm: "হ্যাঁ, ডিলিট করুন",
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      textCancel: "বাতিল",
      cancelTextColor: Colors.black,
      onConfirm: () async {
        try {
          // প্রথমে exam_routines টেবিল থেকে এই এক্সামের সব রুটিন ডিলিট করা
          await supabase.from('exam_routines').delete().eq('exam_id', examId);

          // এরপর exam_titles থেকে এক্সাম কার্ডটি ডিলিট করা
          await supabase.from('exam_titles').delete().eq('id', examId);

          Get.back(); // ডায়ালগ বন্ধ করা
          _fetchExams(); // লিস্ট রিফ্রেশ করা

          Get.snackbar(
            "সফল",
            "পরীক্ষা এবং এর অধীনস্থ সকল রুটিন সফলভাবে ডিলিট করা হয়েছে।",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.back();
          Get.snackbar(
            "ত্রুটি",
            "ডিলিট করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'পরীক্ষার তালিকা',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : examList.isEmpty
          ? const Center(
              child: Text(
                'কোনো পরীক্ষার নাম পাওয়া যায়নি!\nনিচের ফ্লোটিং বাটনে ক্লিক করে যোগ করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: examList.length,
              itemBuilder: (context, index) {
                var exam = examList[index];
                String examId = exam['id'] ?? '';
                String title = exam['exam_title'] ?? '';

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.assignment, color: Colors.white),
                    ),
                    title: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text('রুটিন দেখতে ট্যাপ করুন'),
                    // এডিট এবং ডিলিট করার জন্য ট্রেইলিংয়ে অপশন যোগ করা হয়েছে
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'এডিট করুন',
                          onPressed: () => _showEditExamDialog(examId, title),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'ডিলিট করুন',
                          onPressed: () =>
                              _showDeleteConfirmation(examId, title),
                        ),
                      ],
                    ),
                    onTap: () {
                      // কার্ডে ক্লিক করলে রুটিন তৈরির পেজে চলে যাবে
                      Get.to(
                        () => CreateExamRoutinePage(
                          academyId: widget.academyId,
                          examId: examId,
                          examTitle: title,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddExamDialog,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'এক্সাম যোগ করুন',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
