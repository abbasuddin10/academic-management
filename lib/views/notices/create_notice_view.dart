import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

class CreateNoticeView extends StatefulWidget {
  final String academyId;
  final String userRole;
  final List<String> availableClasses;

  const CreateNoticeView({
    super.key,
    required this.academyId,
    required this.userRole,
    required this.availableClasses,
  });

  @override
  State<CreateNoticeView> createState() => _CreateNoticeViewState();
}

class _CreateNoticeViewState extends State<CreateNoticeView> {
  final supabase = Supabase.instance.client;
  final titleController = TextEditingController();

  final descController = TextEditingController(
    text:
        'সংশ্লিষ্ট সকলের অবগতির জন্য জানানো যাচ্ছে যে, ০৮/০৯/২৬ তারিখে অনুষ্ঠিত স্কলারশিপ লিখিত পরীক্ষা ও সাক্ষাৎকার এবং ০৯/০৯/২৬ তারিখে সাক্ষাতকারের ভিত্তিতে হালি ল্যান্ড কলেজ এ ২২৮ জন শিক্ষার্থীকে মেধা ও অসচ্ছল মেধাবী কোটায় স্কলারশিপ প্রদান করা হলো যার বিস্তারিত ফলাফল প্রতিষ্ঠানের ওয়েব সাইডে প্রকাশ করা হয়েছে। শিক্ষার্থীদের নামের পাশে উল্লেখিত অর্থ শুধুমাত্র হালি ল্যান্ড কলেজ এ অধ্যয়নকালে মাসিক টিউশন ফি এর সাথে সমন্বয় করা হবে।',
  );

  String targetType = 'all_students';
  String? selectedClass;
  File? selectedFile;
  String? selectedFileName;
  bool isUploading = false;
  bool isLoadingAcademy = true;

  Map<String, dynamic>? academyData;
  String generatedMemoNo = '';

  @override
  void initState() {
    super.initState();
    _fetchAcademyDataAndGenerateMemo();
  }

  Future<void> _fetchAcademyDataAndGenerateMemo() async {
    try {
      final res = await supabase
          .from('academies')
          .select()
          .eq('id', widget.academyId)
          .single();

      final timeStamp = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(7);
      final currentYear = DateTime.now().year;

      String academyName = res['academy_name'] ?? 'NOTICE';
      String prefix = academyName.isNotEmpty
          ? academyName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').join('')
          : 'NTC';

      setState(() {
        academyData = res;
        generatedMemoNo = '$prefix/$timeStamp/$currentYear';
        isLoadingAcademy = false;
      });
    } catch (e) {
      setState(() {
        isLoadingAcademy = false;
      });
      print("Academy fetch error: $e");
    }
  }

  String _toBanglaDigits(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bangla = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    for (int i = 0; i < english.length; i++) {
      input = input.replaceAll(english[i], bangla[i]);
    }
    return input;
  }

  String _getDualFormattedDate() {
    final now = DateTime.now();

    const months = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];

    String day = _toBanglaDigits(now.day.toString());
    String month = months[now.month - 1];
    String year = _toBanglaDigits(now.year.toString());
    String englishDateStr = "$day $month, $year খ্রিস্টাব্দ";

    int banglaYear = (now.month < 4 || (now.month == 4 && now.day < 14))
        ? now.year - 594
        : now.year - 593;

    String banglaYearStr = _toBanglaDigits(banglaYear.toString());

    return '''
      <table style="border-collapse: collapse; float: right;">
        <tr>
          <td style="font-weight: bold; padding-right: 8px; vertical-align: middle;">তারিখ:</td>
          <td>
            <div style="text-align: center; font-size: 14px;">২৮ আশ্বিন $banglaYearStr বঙ্গাব্দ</div>
            <div style="border-top: 1px solid #000; margin: 3px 0; width: 170px;"></div>
            <div style="text-align: center; font-size: 14px;">$englishDateStr</div>
          </td>
        </tr>
      </table>
    ''';
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    super.dispose();
  }

  Future<String?> _uploadFileAndGetUrl(File file, String fileName) async {
    try {
      final fileExt = fileName.split('.').last;
      final filePath =
          '${widget.academyId}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

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

  String _generateNoticeHtml({
    required String noticeTitle,
    required String noticeDescription,
  }) {
    final academyName = academyData?['academy_name'] ?? 'শিক্ষা প্রতিষ্ঠান';
    final address = academyData?['address'] ?? '';
    final logoUrl = academyData?['logo_url'] ?? '';
    final principalSignatureUrl = academyData?['principal_signature_url'] ?? '';
    final phone = academyData?['phone'] ?? '';
    final email = academyData?['admin_email'] ?? '';
    final eiin = academyData?['eiin']?.toString() ?? '';
    final academyCode = academyData?['academy_code']?.toString() ?? '';

    final dualDate = _getDualFormattedDate();

    String codeBoxHtml = '';
    if (eiin.isNotEmpty || academyCode.isNotEmpty) {
      codeBoxHtml =
          '''
        <div class="code-box">
          ${academyCode.isNotEmpty ? '<div>কোড: ${_toBanglaDigits(academyCode)}</div>' : ''}
          ${eiin.isNotEmpty ? '<div>EIIN: ${_toBanglaDigits(eiin)}</div>' : ''}
        </div>
      ''';
    }

    List<String> contactParts = [];
    if (phone.isNotEmpty) contactParts.add('মোবাইল: ${_toBanglaDigits(phone)}');
    if (email.isNotEmpty) contactParts.add('ইমেইল: $email');
    String contactStr = contactParts.join(' | ');

    return '''
    <!DOCTYPE html>
    <html lang="bn">
    <head>
        <meta charset="UTF-8">
        <style>
            @page { size: A4; margin: 20mm; }
            body { font-family: 'SolaimanLipi', 'Arial', sans-serif; color: #000; background-color: #fff; margin: 0; padding: 0; }
            .notice-container { width: 100%; max-width: 800px; margin: 0 auto; padding: 20px; box-sizing: border-box; }
            
            .header-table { width: 100%; border-bottom: 3px double #000; padding-bottom: 8px; margin-bottom: 20px; }
            .logo-cell { width: 18%; vertical-align: middle; text-align: left; }
            .logo-cell img { width: 75px; height: 75px; object-fit: contain; }
            
            .code-box {
              border: 1px solid #000;
              font-size: 10px;
              padding: 3px 5px;
              margin-top: 5px;
              display: inline-block;
              text-align: center;
              line-height: 1.2;
            }

            .title-cell { width: 82%; text-align: center; vertical-align: middle; }
            
            /* আলাদা আলাদা ক্লাসে সাইজ ডিফাইন করা হয়েছে যাতে ইচ্ছেমতো পরিবর্তন করা যায় */
            .academy-name-bn { font-size: 35px; font-weight: bold; margin: 0; letter-spacing: 0.5px; }
            .academy-address { font-size: 25px; margin: 3px 0; color: #111; font-weight: normal; }
            .academy-contact { font-size: 14px; margin: 2px 0; color: #333; font-weight: normal; }

            .memo-date-table { width: 100%; margin-top: 15px; margin-bottom: 35px; font-size: 15px; }
            .memo-cell { text-align: left; width: 45%; vertical-align: middle; }
            .date-cell { text-align: right; width: 55%; vertical-align: middle; }

            .notice-heading { text-align: center; font-size: 24px; font-weight: bold; margin: 30px 0 20px 0; letter-spacing: 1px; }
            .notice-body { font-size: 16px; line-height: 1.9; text-align: justify; margin-bottom: 80px; }
            
            .signature-section { float: right; text-align: center; width: 220px; margin-top: 40px; }
            .signature-section img { width: 110px; height: 50px; object-fit: contain; margin-bottom: 5px; }
            .signature-line { border-top: 1px solid #000; margin-top: 5px; padding-top: 5px; font-size: 14px; font-weight: bold; }
            .designation { font-size: 13px; margin: 0; }
        </style>
    </head>
    <body>
        <div class="notice-container">
            <table class="header-table">
                <tr>
                    <td class="logo-cell">
                        ${logoUrl.isNotEmpty ? '<img src="$logoUrl" alt="Logo">' : ''}
                        $codeBoxHtml
                    </td>
                    <td class="title-cell">
                        <!-- প্রতিষ্ঠানের নাম (ফন্ট সাইজ 35px) -->
                        <div class="academy-name-bn">$academyName</div>
                        
                        <!-- প্রতিষ্ঠানের ঠিকানা (ফন্ট সাইজ 25px) -->
                        ${address.isNotEmpty ? '<div class="academy-address">$address</div>' : ''}
                        
                        <!-- যোগাযোগ বা ইমেইল ইনফো (अलग আলাদা ছোট সাইজ) -->
                        ${contactStr.isNotEmpty ? '<div class="academy-contact">$contactStr</div>' : ''}
                    </td>
                </tr>
            </table>

            <table class="memo-date-table">
                <tr>
                    <td class="memo-cell"><b>স্মারক নং:</b> $generatedMemoNo</td>
                    <td class="date-cell">$dualDate</td>
                </tr>
            </table>

            <div class="notice-heading">${noticeTitle.isNotEmpty ? noticeTitle : 'নোটিশ'}</div>

            <div class="notice-body">
                $noticeDescription
            </div>

            <div class="signature-section">
                ${principalSignatureUrl.isNotEmpty ? '<img src="$principalSignatureUrl" alt="Signature">' : ''}
                <div class="signature-line">প্রধান শিক্ষক / অধ্যক্ষ</div>
                <p class="designation">$academyName</p>
            </div>
        </div>
    </body>
    </html>
    ''';
  }

  Future<void> _showNoticePreview() async {
    final htmlContent = _generateNoticeHtml(
      noticeTitle: titleController.text.trim(),
      noticeDescription: descController.text.trim(),
    );

    await Printing.layoutPdf(
      onLayout: (format) async =>
          await Printing.convertHtml(format: format, html: htmlContent),
    );
  }

  Future<void> _submitNotice() async {
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

    setState(() {
      isUploading = true;
    });

    try {
      String? fileUrl;
      if (selectedFile != null && selectedFileName != null) {
        fileUrl = await _uploadFileAndGetUrl(selectedFile!, selectedFileName!);
      }

      await supabase.from('notices').insert({
        'academy_id': widget.academyId,
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'target_type': targetType,
        'target_class': selectedClass,
        'created_by': widget.userRole,
        'file_url': fileUrl,
        'memo_no': generatedMemoNo,
      });

      Get.back(result: true);
      Get.snackbar(
        "সফল",
        "নোটিশ সফলভাবে প্রকাশ করা হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      setState(() {
        isUploading = false;
      });
      Get.snackbar(
        "ত্রুটি",
        "নোটিশ সেভ করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Notice'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: isLoadingAcademy
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      'স্বয়ংক্রিয় তৈরি স্মারক নং: $generatedMemoNo',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),

                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'নোটিশের শিরোনাম',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'বিস্তারিত বিবরণ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            try {
                              FilePickerResult? result =
                                  await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                    ],
                                  );

                              if (result != null &&
                                  result.files.single.path != null) {
                                setState(() {
                                  selectedFile = File(
                                    result.files.single.path!,
                                  );
                                  selectedFileName = result.files.single.name;
                                });
                              }
                            } catch (e) {
                              print("File picker error: $e");
                            }
                          },
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: Text(
                            selectedFileName ?? 'ফাইল/ছবি সংযুক্ত করুন',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 12,
                          ),
                        ),
                        onPressed: _showNoticePreview,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('প্রিভিউ দেখুন'),
                      ),
                    ],
                  ),

                  if (selectedFileName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'সিলেক্টেড ফাইল: $selectedFileName',
                      style: const TextStyle(fontSize: 13, color: Colors.green),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text(
                    'নোটিশের প্রাপক নির্বাচন করুন:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: targetType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
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
                      setState(() {
                        targetType = val!;
                        if (targetType != 'class') {
                          selectedClass = null;
                        }
                      });
                    },
                  ),
                  if (targetType == 'class') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedClass,
                      hint: const Text('ক্লাস সিলেক্ট করুন'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: widget.availableClasses.map((cls) {
                        return DropdownMenuItem(value: cls, child: Text(cls));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedClass = val;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: isUploading ? null : _submitNotice,
                      child: isUploading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'প্রকাশ করুন',
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
    );
  }
}
