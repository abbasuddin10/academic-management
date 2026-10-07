import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentComplaintView extends StatefulWidget {
  final String academyId;
  final String studentId;
  final String studentName;
  final String academyName;
  final String className;
  final String roll;

  const StudentComplaintView({
    super.key,
    required this.academyId,
    required this.studentId,
    required this.studentName,
    required this.academyName,
    required this.className,
    required this.roll,
  });

  @override
  State<StudentComplaintView> createState() => _StudentComplaintViewState();
}

class _StudentComplaintViewState extends State<StudentComplaintView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  bool _isAnonymous = true;
  bool _isSubmitting = false;

  Future<void> _submitComplaint() async {
    if (widget.studentId.isEmpty || widget.academyId.isEmpty) {
      Get.snackbar(
        'ত্রুটি',
        'শিক্ষার্থী বা প্রতিষ্ঠানের আইডি পাওয়া যায়নি।',
        backgroundColor: Colors.red.shade50,
        colorText: Colors.red.shade900,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final supabase = Supabase.instance.client;

      String savedName = _isAnonymous ? 'Anonymous' : widget.studentName;
      String savedRoll = _isAnonymous ? 'Anonymous' : widget.roll;
      String savedClass = _isAnonymous ? 'Anonymous' : widget.className;

      await supabase.from('complaints').insert({
        'academy_id': widget.academyId,
        'student_id': widget.studentId,
        'student_name': savedName,
        'class_name': savedClass,
        'roll': savedRoll,
        'is_anonymous': _isAnonymous,
        'title': _titleController.text.trim(),
        'details': _detailsController.text.trim(),
        'status': 'Pending',
      });

      _titleController.clear();
      _detailsController.clear();

      Get.snackbar(
        'সফল',
        _isAnonymous
            ? 'আপনার অভিযোগটি সম্পূর্ণ গোপনীয়তার সাথে জমা দেওয়া হয়েছে।'
            : 'আপনার অভিযোগটি সফলভাবে জমা দেওয়া হয়েছে।',
        backgroundColor: Colors.green.shade50,
        colorText: Colors.green.shade900,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        icon: const Icon(Icons.check_circle, color: Colors.green),
      );
    } catch (e) {
      Get.snackbar(
        'ত্রুটি',
        'অভিযোগ পাঠাতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red.shade50,
        colorText: Colors.red.shade900,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        icon: const Icon(Icons.error, color: Colors.red),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showConfirmDialog() {
    if (!_formKey.currentState!.validate()) return;

    Get.defaultDialog(
      title: "অভিযোগ জমা কনফার্মেশন",
      titleStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 17,
        color: Colors.indigo,
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          _isAnonymous
              ? "আপনি কি নিশ্চিত? আপনার পরিচয় সম্পূর্ণ গোপন (Anonymous) রেখে অভিযোগটি কর্তৃপক্ষের কাছে পাঠানো হবে।"
              : "আপনি কি নিশ্চিত? আপনার নাম (${widget.studentName}) এবং ক্লাসসহ অভিযোগটি পাঠানো হবে।",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: Colors.black87),
        ),
      ),
      textConfirm: "হ্যাঁ, জমা দিন",
      textCancel: "না",
      confirmTextColor: Colors.white,
      buttonColor: Colors.indigo,
      cancelTextColor: Colors.black54,
      onConfirm: () {
        Get.back();
        _submitComplaint();
      },
    );
  }

  void _showComplaintHistory() {
    if (widget.studentId.isEmpty) {
      Get.snackbar('ত্রুটি', 'শিক্ষার্থীর আইডি পাওয়া যায়নি।');
      return;
    }

    Get.bottomSheet(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setStateSheet) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'আমার জমাকৃত অভিযোগসমূহ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: Supabase.instance.client
                        .from('complaints')
                        .select()
                        .eq('student_id', widget.studentId)
                        .order('created_at', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'হিস্ট্রি লোড করতে সমস্যা হচ্ছে। RLS পলিসি চেক করুন।\n\nত্রুটি: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }
                      final complaints = snapshot.data ?? [];
                      if (complaints.isEmpty) {
                        return const Center(
                          child: Text(
                            'আপনি এখনো কোনো অভিযোগ জমা দেননি।',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: complaints.length,
                        itemBuilder: (context, index) {
                          final item = complaints[index];
                          final complaintId = item['id'].toString();
                          String status = item['status'] ?? 'Pending';
                          Color statusColor = status == 'Resolved'
                              ? Colors.green
                              : Colors.orange;

                          String dateStr = '';
                          if (item['created_at'] != null) {
                            try {
                              dateStr = item['created_at'].toString().substring(
                                0,
                                10,
                              );
                            } catch (_) {
                              dateStr = '';
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['title'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              status,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          // শুধু পেন্ডিং থাকলেই ডিলিট আইকন দেখাবে
                                          if (status == 'Pending') ...[
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: 'অভিযোগ ডিলিট করুন',
                                              onPressed: () {
                                                Get.defaultDialog(
                                                  title: "ডিলিট কনফার্মেশন",
                                                  middleText:
                                                      "আপনি কি নিশ্চিতভাবে এই অভিযোগটি মুছে ফেলতে চান?",
                                                  textConfirm: "হ্যাঁ, ডিলিট",
                                                  textCancel: "না",
                                                  confirmTextColor:
                                                      Colors.white,
                                                  buttonColor: Colors.red,
                                                  onConfirm: () async {
                                                    Get.back(); // ডায়ালগ বন্ধ
                                                    try {
                                                      await Supabase
                                                          .instance
                                                          .client
                                                          .from('complaints')
                                                          .delete()
                                                          .eq(
                                                            'id',
                                                            complaintId,
                                                          );

                                                      setStateSheet(
                                                        () {},
                                                      ); // শিট রিফ্রেশ
                                                      Get.snackbar(
                                                        'সফল',
                                                        'অভিযোগটি সফলভাবে মুছে ফেলা হয়েছে।',
                                                        backgroundColor: Colors
                                                            .green
                                                            .shade50,
                                                        colorText: Colors
                                                            .green
                                                            .shade900,
                                                      );
                                                    } catch (e) {
                                                      Get.snackbar(
                                                        'ত্রুটি',
                                                        'ডিলিট করতে সমস্যা হয়েছে: $e',
                                                        backgroundColor:
                                                            Colors.red.shade50,
                                                        colorText:
                                                            Colors.red.shade900,
                                                      );
                                                    }
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item['details'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'তারিখ: $dateStr',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      isScrollControlled: true,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'অভিযোগ ও মতামত',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: TextButton.icon(
              onPressed: _showComplaintHistory,
              label: const Text(
                'অভিযোগ দেখুন',
                style: TextStyle(
                  color: Color.fromARGB(255, 217, 255, 5),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: Colors.blue,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'আপনার যেকোনো সমস্যা বা মতামত সম্পূর্ণ নির্দ্বিধায় এখানে জানাতে পারেন। আপনি চাইলে আপনার পরিচয় গোপন রাখতে পারেন অথবা নাম প্রকাশ করেও পাঠাতে পারেন। ভয় পাওয়ার কিছু নেই, এটি আপনাদের কল্যাণের জন্যই!',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blue.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'অভিযোগের বিবরণ দিন',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'অভিযোগ বা বিষয়ের নাম',
                        hintText: 'যেমন: পরিবেশ বা অন্যান্য সমস্যা',
                        prefixIcon: const Icon(
                          Icons.title,
                          color: Colors.indigo,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'দয়া করে বিষয়ের নাম লিখুন';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _detailsController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'বিস্তারিত বিবরণ',
                        hintText: 'আপনার সমস্যাটি খুলে বলুন...',
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 80),
                          child: Icon(Icons.description, color: Colors.indigo),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'দয়া করে বিস্তারিত লিখুন';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 20),
                    CheckboxListTile(
                      value: _isAnonymous,
                      onChanged: (bool? value) {
                        setState(() {
                          _isAnonymous = value ?? true;
                        });
                      },
                      title: const Text(
                        'আমার পরিচয় (নাম ও রোল) গোপন রাখুন',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        _isAnonymous
                            ? 'ডাটাবেজে নাম হিসেবে Anonymous সেভ হবে।'
                            : 'আপনার নাম ও ক্লাসসহ অভিযোগ জমা হবে।',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      activeColor: Colors.indigo,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _showConfirmDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'অভিযোগ জমা দিন',
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
      ),
    );
  }
}
