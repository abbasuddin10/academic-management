import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

class QuestionPaperDownloadAdmin extends StatefulWidget {
  final String academyId;
  final String examTitleId;
  final String examTitle;

  const QuestionPaperDownloadAdmin({
    super.key,
    required this.academyId,
    required this.examTitleId,
    required this.examTitle,
  });

  @override
  State<QuestionPaperDownloadAdmin> createState() =>
      _QuestionPaperDownloadAdminState();
}

class _QuestionPaperDownloadAdminState
    extends State<QuestionPaperDownloadAdmin> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allFilesList = [];
  List<String> _classList = ['সকল প্রশ্ন'];
  String _selectedClass = 'সকল প্রশ্ন';

  @override
  void initState() {
    super.initState();
    _fetchExamFilesAndClasses();
  }

  // সুপাবেস থেকে নির্দিষ্ট একাডেমি ও পরীক্ষার সব ফাইল ফেচ করা
  Future<void> _fetchExamFilesAndClasses() async {
    try {
      final response = await supabase
          .from('exam_files')
          .select('*')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', widget.examTitle)
          .order('created_at', ascending: false);

      if (response != null && mounted) {
        List<Map<String, dynamic>> files = List<Map<String, dynamic>>.from(
          response,
        );

        Set<String> uniqueClasses = {'সকল প্রশ্ন'};
        for (var file in files) {
          String className = file['class_name']?.toString().trim() ?? '';
          if (className.isNotEmpty) {
            uniqueClasses.add(className);
          }
        }

        setState(() {
          _allFilesList = files;
          _classList = uniqueClasses.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // একক ফাইল ডাউনলোড করার ফাংশন
  Future<void> _downloadFile(String url, String subjectName) async {
    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

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

      Directory tempDir = await getTemporaryDirectory();
      String cleanSubject = subjectName
          .replaceAll(RegExp(r'[^\w\s]+'), '')
          .trim()
          .replaceAll(' ', '_');
      String fileName =
          '${cleanSubject}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      String savePath = '${tempDir.path}/$fileName';

      await Dio().download(url, savePath);
      Get.back();

      Get.snackbar(
        'ডাউনলোড সফল',
        'ফাইলটি সফলভাবে ডাউনলোড হয়েছে!',
        backgroundColor: Colors.teal,
        colorText: Colors.white,
      );
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'ত্রুটি',
        'ডাউনলোড করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ফাইল ভিউ বা ওপেন করার ফাংশন
  Future<void> _viewFile(String url) async {
    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      Directory tempDir = await getTemporaryDirectory();
      String fileName = 'view_${DateTime.now().millisecondsSinceEpoch}.pdf';
      String savePath = '${tempDir.path}/$fileName';

      await Dio().download(url, savePath);
      Get.back();

      await OpenFilex.open(savePath);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'ত্রুটি',
        'ফাইল ওপেন করা যায়নি: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // সিলেক্ট করা ক্লাসের বা সকল ফাইল একসাথে ডাউনলোড করার লজিক
  Future<void> _downloadAllSelectedFiles(
    List<Map<String, dynamic>> listToDownload,
  ) async {
    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      barrierDismissible: false,
    );

    try {
      int successCount = 0;
      Directory? downloadDir;

      if (Platform.isAndroid) {
        downloadDir = await getExternalStorageDirectory();
        downloadDir ??= await getApplicationDocumentsDirectory();
      } else {
        downloadDir = await getApplicationDocumentsDirectory();
      }

      for (var item in listToDownload) {
        String fileUrl = item['file_url'] ?? '';
        String subjectName = item['subject_name'] ?? 'subject';

        if (fileUrl.isNotEmpty) {
          try {
            String extension = 'pdf';
            String lowerUrl = fileUrl.toLowerCase();
            if (lowerUrl.contains('.jpg') || lowerUrl.contains('.jpeg')) {
              extension = 'jpg';
            } else if (lowerUrl.contains('.png')) {
              extension = 'png';
            }

            String cleanSubject = subjectName
                .replaceAll(RegExp(r'[^\w\s]+'), '')
                .trim()
                .replaceAll(' ', '_');
            String fileName =
                '${cleanSubject}_${DateTime.now().millisecondsSinceEpoch}.$extension';
            String savePath = '${downloadDir.path}/$fileName';

            await Dio().download(fileUrl, savePath);
            successCount++;
          } catch (_) {}
        }
      }

      if (Get.isDialogOpen ?? false) {
        Get.back(); // লোডিং বন্ধ
      }

      Get.snackbar(
        'ডাউনলোড সম্পন্ন',
        'মোট $successCount টি ফাইল সফলভাবে ডাউনলোড হয়েছে!',
        backgroundColor: Colors.teal,
        colorText: Colors.white,
      );
    } catch (e) {
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      Get.snackbar(
        'ত্রুটি',
        'ফাইলগুলো ডাউনলোড করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  String _formatBangladeshTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      DateTime utcDate = DateTime.parse(timestamp).toUtc();
      DateTime bdDate = utcDate.add(const Duration(hours: 6));
      return DateFormat('dd MMM yyyy, hh:mm a').format(bdDate);
    } catch (e) {
      return timestamp.substring(0, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredList = _selectedClass == 'সকল প্রশ্ন'
        ? _allFilesList
        : _allFilesList
              .where((item) => item['class_name'] == _selectedClass)
              .toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.examTitle),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // অ্যাপবারে সব একসাথে ডাউনলোডের আইকন
          IconButton(
            icon: const Icon(Icons.download_for_offline),
            tooltip: 'সকল ফাইল ডাউনলোড করুন',
            onPressed: () {
              if (filteredList.isEmpty) {
                Get.snackbar(
                  'সতর্কতা',
                  'ডাউনলোড করার মতো কোনো ফাইল বা প্রশ্ন নেই!',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              _downloadAllSelectedFiles(filteredList);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ক্লাসের হরাইজন্টাল স্ক্রোলিং ফিল্টার বার
                Container(
                  height: 55,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.white,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _classList.length,
                    itemBuilder: (context, index) {
                      String className = _classList[index];
                      bool isSelected = (className == _selectedClass);

                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(className),
                          selected: isSelected,
                          selectedColor: Colors.deepPurple,
                          backgroundColor: Colors.grey.shade200,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          onSelected: (bool selected) {
                            setState(() {
                              _selectedClass = className;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1, thickness: 1),

                // ফাইল বা প্রশ্নগুলোর কার্ড লিস্ট
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(
                          child: Text(
                            'এই ক্যাটাগরিতে কোনো প্রশ্ন বা ফাইল পাওয়া যায়নি।',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final item = filteredList[index];
                            String subjectName =
                                item['subject_name'] ?? 'বিষয় নামহীন';
                            String uploaderName =
                                item['uploader_name'] ?? 'অজানা শিক্ষক';
                            String className = item['class_name'] ?? '';
                            String fileUrl = item['file_url'] ?? '';
                            String formattedTime = _formatBangladeshTime(
                              item['created_at'],
                            );

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          Colors.deepPurple.shade50,
                                      child: const Icon(
                                        Icons.insert_drive_file,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'বিষয়: $subjectName',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'শ্রেণি: $className | আপলোডকারী: $uploaderName',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'সময়: $formattedTime',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ভিউ বা প্রিভিউ আইকন
                                    IconButton(
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'ভিউ করুন',
                                      onPressed: () {
                                        if (fileUrl.isNotEmpty) {
                                          _viewFile(fileUrl);
                                        } else {
                                          Get.snackbar(
                                            'ত্রুটি',
                                            'ফাইলের লিংক পাওয়া যায়নি',
                                            backgroundColor: Colors.red,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                    ),
                                    // একক ডাউনলোড আইকন
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download,
                                        color: Colors.deepPurple,
                                      ),
                                      tooltip: 'ডাউনলোড',
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
    );
  }
}
