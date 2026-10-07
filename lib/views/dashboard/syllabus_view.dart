import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart'; // dio ইম্পোর্ট করুন
import 'package:path_provider/path_provider.dart'; // path_provider ইম্পোর্ট করুন
import 'dart:io';

class SyllabusView extends StatefulWidget {
  final String academyId;
  final String userRole;

  const SyllabusView({
    Key? key,
    required this.academyId,
    required this.userRole,
  }) : super(key: key);

  @override
  State<SyllabusView> createState() => _SyllabusViewState();
}

class _SyllabusViewState extends State<SyllabusView> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> classesList = [];
  Map<String, bool> uploadedStatus = {};
  bool isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _fetchClassesAndSyllabusStatus();
  }

  // ১. ক্লাস এবং কোন ক্লাসের সিলেবাস আপলোড করা আছে তা ফেচ করা
  Future<void> _fetchClassesAndSyllabusStatus() async {
    try {
      setState(() {
        isLoadingData = true;
      });

      final classResponse = await supabase
          .from('classes')
          .select()
          .eq('academy_id', widget.academyId);

      if (classResponse != null) {
        classesList = List<Map<String, dynamic>>.from(classResponse);
      }

      final syllabusResponse = await supabase
          .from('syllabus_files')
          .select('class_name')
          .eq('academy_id', widget.academyId);

      uploadedStatus.clear();
      if (syllabusResponse != null) {
        for (var item in syllabusResponse) {
          String cName = (item['class_name'] ?? '').toString().trim();
          if (cName.isNotEmpty) {
            uploadedStatus[cName] = true;
          }
        }
      }

      setState(() {
        isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        isLoadingData = false;
      });
      print("Syllabus status fetch error: $e");
    }
  }

  // ৩. পপ-আপ ছাড়া সরাসরি ভিউ করার ফাংশন
  Future<void> _openSyllabusFile(String className) async {
    try {
      final response = await supabase
          .from('syllabus_files')
          .select('file_url')
          .eq('academy_id', widget.academyId)
          .eq('class_name', className)
          .order('created_at', ascending: false)
          .limit(1);

      if (response != null && (response as List).isNotEmpty) {
        String fileUrl = response[0]['file_url'] ?? '';

        if (fileUrl.isNotEmpty) {
          final Uri uri = Uri.parse(fileUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            Get.snackbar(
              "ত্রুটি",
              "ফাইলটি ওপেন করা সম্ভব হচ্ছে না!",
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
        } else {
          Get.snackbar(
            "দুঃখিত",
            "ফাইলের লিংক পাওয়া যায়নি।",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }
      } else {
        Get.snackbar(
          "তথ্য নেই",
          "এই ক্লাসের জন্য কোনো সিলেবাস আপলোড করা হয়নি।",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ফাইল ওপেন করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ৪. পার্সেন্টেজ প্রোগ্রেস সহ ফাইল ডাউনলোডের ফাংশন
  Future<void> _downloadSyllabusFile(String className) async {
    try {
      // প্রথমে ডাটাবেজ থেকে ফাইলের লিংক ফেচ করা
      final response = await supabase
          .from('syllabus_files')
          .select('file_url')
          .eq('academy_id', widget.academyId)
          .eq('class_name', className)
          .order('created_at', ascending: false)
          .limit(1);

      if (response == null || (response as List).isEmpty) {
        Get.snackbar(
          "তথ্য নেই",
          "ডাউনলোড করার মত কোনো ফাইল পাওয়া যায়নি।",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      String fileUrl = response[0]['file_url'] ?? '';
      if (fileUrl.isEmpty) {
        Get.snackbar(
          "ত্রুটি",
          "ফাইলের লিংক সঠিক নয়।",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // ডাউনলোডের জন্য ফোল্ডার পাথ নির্ধারণ (Downloads ফোল্ডার বা এক্সটার্নাল ডিরেক্টরি)
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String fileName =
          "syllabus_${className}_${DateTime.now().millisecondsSinceEpoch}.pdf";
      String savePath = "${directory!.path}/$fileName";

      // প্রোগ্রেস দেখানোর জন্য ডায়ালগ ওপেন করা
      ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'সিলেবাস ডাউনলোড হচ্ছে...',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, value, child) {
                      return Column(
                        children: [
                          LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.teal.shade50,
                            color: Colors.teal,
                            minHeight: 8,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "${(value * 100).toStringAsFixed(0)}%",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Dio দিয়ে ফাইল ডাউনলোড শুরু করা
      Dio dio = Dio();
      await dio.download(
        fileUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            progressNotifier.value = received / total;
          }
        },
      );

      // ডায়ালগ বন্ধ করা
      Navigator.pop(context);

      Get.snackbar(
        "সফল",
        "ফাইল সফলভাবে ডাউনলোড হয়েছে!\nসেভ হয়েছে: $savePath",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      // যদি ডায়ালগ খোলা থাকে তবে তা বন্ধ করা
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      Get.snackbar(
        "ডাউনলোড ব্যর্থ",
        "ত্রুটি: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ২. আপলোড পপ-আপ ওপেন করার ফাংশন
  void _showUploadDialog(String className) {
    List<File> selectedFiles = [];
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> _pickFiles() async {
              try {
                FilePickerResult? result = await FilePicker.pickFiles(
                  allowMultiple: true,
                  type: FileType.custom,
                  allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                );

                if (result != null) {
                  setDialogState(() {
                    selectedFiles = result.paths
                        .map((path) => File(path!))
                        .toList();
                  });
                }
              } catch (e) {
                Get.snackbar(
                  "ত্রুটি",
                  "ফাইল সিলেক্ট করতে সমস্যা হয়েছে: $e",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            }

            Future<void> _uploadToSupabase() async {
              if (selectedFiles.isEmpty) return;

              setDialogState(() {
                isUploading = true;
              });

              try {
                final now = DateTime.now();

                for (int i = 0; i < selectedFiles.length; i++) {
                  var file = selectedFiles[i];

                  final originalPath = file.path;
                  final fileExtension = originalPath.contains('.')
                      ? originalPath.split('.').last
                      : 'file';

                  final fileName =
                      'syllabus_${now.millisecondsSinceEpoch}_$i.$fileExtension';
                  final filePath = '${widget.academyId}/$fileName';

                  await supabase.storage
                      .from('syllabuses')
                      .upload(filePath, file);

                  final publicUrl = supabase.storage
                      .from('syllabuses')
                      .getPublicUrl(filePath);

                  await supabase.from('syllabus_files').insert({
                    'academy_id': widget.academyId,
                    'class_name': className,
                    'file_url': publicUrl,
                    'created_at': now.toIso8601String(),
                  });
                }

                Navigator.pop(context);

                setState(() {
                  uploadedStatus[className] = true;
                });

                Get.snackbar(
                  "সফল",
                  "$className-এর সিলেবাস সফলভাবে আপলোড হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                setDialogState(() {
                  isUploading = false;
                });
                Get.snackbar(
                  "আপলোড ব্যর্থ",
                  "ত্রুটি: $e",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(
                'সিলেবাস আপলোড ($className)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'লোকাল ডিভাইস থেকে PDF অথবা ছবি (মাল্টিপল) সিলেক্ট করুন:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: isUploading ? null : _pickFiles,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('ফাইল সিলেক্ট করুন'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade50,
                        foregroundColor: Colors.teal,
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedFiles.isNotEmpty)
                      Text(
                        'নির্বাচিত ফাইল সংখ্যা: ${selectedFiles.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    if (isUploading) ...[
                      const SizedBox(height: 15),
                      const CircularProgressIndicator(color: Colors.teal),
                      const SizedBox(height: 8),
                      const Text(
                        'আপলোড হচ্ছে, দয়া করে অপেক্ষা করুন...',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text(
                    'বাতিল',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                if (selectedFiles.isNotEmpty && !isUploading)
                  ElevatedButton(
                    onPressed: _uploadToSupabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('আপলোড করুন'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'সিলেবাস তালিকা',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.teal,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : classesList.isEmpty
          ? const Center(
              child: Text(
                'কোনো ক্লাস পাওয়া যায়নি।',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: classesList.length,
              padding: const EdgeInsets.all(12.0),
              itemBuilder: (context, index) {
                var cls = classesList[index];
                String className =
                    cls['name'] ?? cls['class_name'] ?? 'অজানা ক্লাস';

                bool isUploaded = uploadedStatus[className] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.shade200, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.menu_book_rounded,
                                color: Colors.teal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                className,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.teal.shade100,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                label: 'ভিউ',
                                icon: Icons.visibility,
                                color: Colors.blue.shade700,
                                bgColor: Colors.blue.shade50,
                                onTap: () => _openSyllabusFile(className),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildActionButton(
                                label: 'ডাউনলোড',
                                icon: Icons.download,
                                color: Colors.green.shade700,
                                bgColor: Colors.green.shade50,
                                onTap: () => _downloadSyllabusFile(
                                  className,
                                ), // প্রোগ্রেস সহ ডাউনলোড ফাংশন যুক্ত করা হলো
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildActionButton(
                                label: isUploaded ? 'রি-আপলোড' : 'আপলোড',
                                icon: isUploaded ? Icons.refresh : Icons.upload,
                                color: isUploaded
                                    ? Colors.purple.shade700
                                    : Colors.deepOrange.shade700,
                                bgColor: isUploaded
                                    ? Colors.purple.shade50
                                    : Colors.deepOrange.shade50,
                                onTap: () => _showUploadDialog(className),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
