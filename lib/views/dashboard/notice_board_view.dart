import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class NoticeBoardView extends StatefulWidget {
  final String academyId;
  final String userRole; // 'super_admin', 'teacher', etc.

  const NoticeBoardView({
    super.key,
    required this.academyId,
    required this.userRole,
  });

  @override
  State<NoticeBoardView> createState() => _NoticeBoardViewState();
}

class _NoticeBoardViewState extends State<NoticeBoardView> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> noticesList = [];
  List<String> availableClasses = [];

  @override
  void initState() {
    super.initState();
    _fetchNotices();
    if (widget.userRole == 'super_admin') {
      _fetchClasses();
    }
  }

  Future<void> _fetchClasses() async {
    try {
      final res = await supabase
          .from('students')
          .select('class')
          .eq('academy_id', widget.academyId);

      Set<String> classes = {};
      for (var item in (res as List)) {
        String? cls = item['class']?.toString().trim();
        if (cls != null && cls.isNotEmpty) {
          classes.add(cls);
        }
      }
      setState(() {
        availableClasses = classes.toList();
      });
    } catch (e) {
      print("Error fetching classes: $e");
    }
  }

  Future<void> _fetchNotices() async {
    try {
      setState(() => isLoading = true);
      var query = supabase
          .from('notices')
          .select()
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      final response = await query;
      setState(() {
        noticesList = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar(
        "ত্রুটি",
        "নোটিশ লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ফাইল বা ইমেজ সিলেক্ট ও আপলোড করার ফাংশন
  Future<String?> _uploadFileAndGetUrl(File file, String fileName) async {
    try {
      final fileExt = fileName.split('.').last;
      final filePath =
          '${widget.academyId}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Supabase storage bucket নাম 'notices_files' হতে হবে (অথবা আপনার ইচ্ছেমতো)
      await supabase.storage.from('notices_files').upload(filePath, file);

      final publicUrl = supabase.storage
          .from('notices_files')
          .getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  void _showCreateNoticeDialog() {
    // শুধুমাত্র super_admin নোটিশ দিতে পারবে
    if (widget.userRole != 'super_admin') {
      Get.snackbar(
        "অপারেশন নিষেধ",
        "শুধুমাত্র অ্যাডমিন নোটিশ প্রকাশ করতে পারবেন!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final titleController = TextEditingController();
    final descController = TextEditingController();
    String targetType = 'all_students';
    String? selectedClass;
    File? selectedFile;
    String? selectedFileName;

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'নতুন নোটিশ ও ফাইল তৈরি করুন',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'নোটিশের শিরোনাম',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'বিস্তারিত বিবরণ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ফাইল বা ইমেজ সিলেক্ট করার বাটন
                  // ফাইল বা ইমেজ সিলেক্ট করার বাটন
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        // প্ল্যাটফর্ম প্রপার্টি ছাড়া সরাসরি pickFiles কল করা
                        FilePickerResult? result = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                        );

                        if (result != null &&
                            result.files.single.path != null) {
                          setStateDialog(() {
                            selectedFile = File(result.files.single.path!);
                            selectedFileName = result.files.single.name;
                          });
                        }
                      } catch (e) {
                        print("File picker error: $e");
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(selectedFileName ?? 'ফাইল বা ছবি সংযুক্ত করুন'),
                  ),
                  if (selectedFileName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'সিলেক্টেড: $selectedFileName',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Text(
                    'নোটিশের প্রাপক নির্বাচন করুন:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: targetType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'all_students',
                        child: Text('সকল ছাত্র-ছাত্রী'),
                      ),
                      DropdownMenuItem(
                        value: 'class',
                        child: Text('নির্দিষ্ট একটি ক্লাস'),
                      ),
                      DropdownMenuItem(
                        value: 'teachers',
                        child: Text('সকল শিক্ষক'),
                      ),
                      DropdownMenuItem(
                        value: 'everyone',
                        child: Text('সবাই (শিক্ষক ও ছাত্র)'),
                      ),
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        targetType = val!;
                        if (targetType != 'class') {
                          selectedClass = null;
                        }
                      });
                    },
                  ),
                  if (targetType == 'class') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedClass,
                      hint: const Text('ক্লাস সিলেক্ট করুন'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                      ),
                      items: availableClasses.map((cls) {
                        return DropdownMenuItem(value: cls, child: Text(cls));
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedClass = val;
                        });
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (titleController.text.trim().isEmpty ||
                  descController.text.trim().isEmpty) {
                Get.snackbar(
                  "সতর্কতা",
                  "শিরোনাম ও বিবরণ আবশ্যক!",
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              if (targetType == 'class' && selectedClass == null) {
                Get.snackbar(
                  "সতর্কতা",
                  "দয়া করে ক্লাস সিলেক্ট করুন!",
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }

              Get.back();

              // লোডিং ডায়ালগ দেখানো
              Get.dialog(
                const Center(
                  child: CircularProgressIndicator(color: Colors.teal),
                ),
                barrierDismissible: false,
              );

              try {
                String? fileUrl;
                if (selectedFile != null && selectedFileName != null) {
                  fileUrl = await _uploadFileAndGetUrl(
                    selectedFile!,
                    selectedFileName!,
                  );
                }

                await supabase.from('notices').insert({
                  'academy_id': widget.academyId,
                  'title': titleController.text.trim(),
                  'description': descController.text.trim(),
                  'target_type': targetType,
                  'target_class': selectedClass,
                  'created_by': widget.userRole,
                  'file_url': fileUrl, // ডাটাবেজে ফাইলের লিংক সেভ হবে
                });

                Get.back(); // লোডিং বন্ধ
                Get.snackbar(
                  "সফল",
                  "নোটিশ সফলভাবে ফাইলসহ প্রকাশ করা হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
                _fetchNotices();
              } catch (e) {
                Get.back(); // লোডিং বন্ধ
                Get.snackbar(
                  "ত্রুটি",
                  "নোটিশ সেভ করতে সমস্যা হয়েছে: $e",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text('প্রকাশ করুন'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = (widget.userRole == 'super_admin');

    return Scaffold(
      appBar: AppBar(
        title: const Text('নোটিশ বোর্ড'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              onPressed: _showCreateNoticeDialog,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'নোটিশ দিন',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : noticesList.isEmpty
          ? const Center(
              child: Text(
                'এই মুহূর্তে কোনো নোটিশ নেই।',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchNotices,
              child: ListView.builder(
                itemCount: noticesList.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final notice = noticesList[index];
                  String targetText = '';
                  String tType = notice['target_type'] ?? '';
                  if (tType == 'all_students')
                    targetText = 'প্রাপক: সকল ছাত্র-ছাত্রী';
                  else if (tType == 'class')
                    targetText = 'প্রাপক ক্লাস: ${notice['target_class']}';
                  else if (tType == 'teachers')
                    targetText = 'প্রাপক: সকল শিক্ষক';
                  else
                    targetText = 'প্রাপক: সকলের জন্য';

                  String? fileUrl = notice['file_url'];

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
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
                              const Icon(
                                Icons.campaign,
                                color: Colors.teal,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notice['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notice['description'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),

                          // যদি ফাইল বা ইমেজ থাকে তবে ডাউনলোডের বা দেখার বাটন দেখাবে
                          if (fileUrl != null && fileUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                side: const BorderSide(color: Colors.teal),
                              ),
                              onPressed: () {
                                // এখানে সরাসরি ব্রাউজারে বা Get.to দিয়ে ফাইল ওপেন করা যাবে
                                // যেমন: launchUrl(Uri.parse(fileUrl));
                              },
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('সংযুক্ত ফাইল/ডকুমেন্ট দেখুন'),
                            ),
                          ],

                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  targetText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.teal.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                notice['created_at'] != null
                                    ? notice['created_at'].toString().substring(
                                        0,
                                        10,
                                      )
                                    : '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
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
