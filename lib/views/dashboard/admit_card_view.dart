import 'dart:typed_data' as pw;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image_picker/image_picker.dart';

class AdmitCardView extends StatefulWidget {
  final String academyId;

  const AdmitCardView({super.key, required this.academyId});

  @override
  State<AdmitCardView> createState() => _AdmitCardViewState();
}

class _AdmitCardViewState extends State<AdmitCardView> {
  final supabase = Supabase.instance.client;
  String selectedClass = 'সব ক্লাস';
  bool isLoading = true;
  List<Map<String, dynamic>> allStudents = [];
  Map<String, List<Map<String, dynamic>>> groupedStudents = {};
  Map<String, int> classCounts = {};
  List<String> classList = [];

  List<String> examList = [];
  String? selectedExam;

  Map<String, dynamic>? academyInfo;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  final ScreenshotController _admitCardScreenshotController =
      ScreenshotController();

  @override
  void initState() {
    super.initState();
    _fetchAcademyAndData();
    _searchController.addListener(() {
      setState(() {
        searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _compareClassNames(String a, String b) {
    if (a == 'সব ক্লাস') return -1;
    if (b == 'সব ক্লাস') return 1;

    List<String> customOrder = [
      'play',
      'প্লে',
      'nursery',
      'নার্সারি',
      'kg',
      'কেজি',
      'class 1',
      'class i',
      '১ম শ্রেণি',
      'প্রথম শ্রেণি',
      'one',
      'class 2',
      'class ii',
      '২য় শ্রেণি',
      'দ্বিতীয় শ্রেণি',
      'two',
      'class 3',
      'class iii',
      '৩য় শ্রেণি',
      'তৃতীয় শ্রেণি',
      'three',
      'class 4',
      'class iv',
      '৪র্থ শ্রেণি',
      'চতুর্থ শ্রেণি',
      'four',
      'class 5',
      'class v',
      '৫ম শ্রেণি',
      'পঞ্চম শ্রেণি',
      'five',
      'class 6',
      'class vi',
      '৬ষ্ঠ শ্রেণি',
      'ষষ্ঠ শ্রেণি',
      'six',
      'class 7',
      'class vii',
      '৭ম শ্রেণি',
      'সপ্তম শ্রেণি',
      'seven',
      'class 8',
      'class viii',
      '৮ম শ্রেণি',
      'অষ্টম শ্রেণি',
      'eight',
      'class 9',
      'class ix',
      '৯ম শ্রেণি',
      'নবম শ্রেণি',
      'nine',
      'class 10',
      'class x',
      '১০ম শ্রেণি',
      'দশম শ্রেণি',
      'ten',
    ];

    int indexA = customOrder.indexWhere(
      (item) => a.toLowerCase().contains(item),
    );
    int indexB = customOrder.indexWhere(
      (item) => b.toLowerCase().contains(item),
    );

    if (indexA != -1 && indexB != -1) {
      return indexA.compareTo(indexB);
    } else if (indexA != -1) {
      return -1;
    } else if (indexB != -1) {
      return 1;
    }

    return a.compareTo(b);
  }

  Future<void> _fetchAcademyAndData() async {
    try {
      final academyResponse = await supabase
          .from('academies')
          .select('*')
          .eq('id', widget.academyId)
          .maybeSingle();

      if (academyResponse != null) {
        academyInfo = academyResponse;
      }

      final examTitlesResponse = await supabase
          .from('exam_titles')
          .select('exam_title, created_at')
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      if (examTitlesResponse != null) {
        List list = examTitlesResponse as List;
        List<String> exams = [];
        for (var item in list) {
          String title = item['exam_title']?.toString().trim() ?? '';
          if (title.isNotEmpty && !exams.contains(title)) {
            exams.add(title);
          }
        }
        examList = exams;
        if (examList.isNotEmpty) {
          selectedExam = examList.first;
        }
      }

      final response = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', widget.academyId);

      if (response != null) {
        final List list = response as List;
        allStudents = list.map((e) => Map<String, dynamic>.from(e)).toList();

        groupedStudents.clear();
        Map<String, int> counts = {};
        counts['সব ক্লাস'] = allStudents.length;

        Set<String> classes = {};
        List<Map<String, dynamic>> allList = [];

        for (var student in allStudents) {
          String className =
              student['class']?.toString().trim() ??
              student['class_name']?.toString().trim() ??
              'অন্যান্য ক্লাস';

          if (className.isNotEmpty) {
            classes.add(className);
            counts[className] = (counts[className] ?? 0) + 1;
            groupedStudents.putIfAbsent(className, () => []).add(student);
          }
          allList.add(student);
        }
        groupedStudents['সব ক্লাস'] = allList;

        classList = classes.toList();
        classList.sort(_compareClassNames);
        classList.insert(0, 'সব ক্লাস');
        classCounts = counts;
      }
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ডাটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showUploadAssetsDialog() {
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool uploading = false;

            Future<void> uploadImage(String columnField) async {
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (image == null) return;

              setDialogState(() => uploading = true);
              try {
                final bytes = await image.readAsBytes();
                final fileExt = image.name.split('.').last;
                final fileName =
                    '${widget.academyId}_${columnField}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

                await supabase.storage
                    .from('academy_assets')
                    .uploadBinary(fileName, bytes);
                final imageUrl = supabase.storage
                    .from('academy_assets')
                    .getPublicUrl(fileName);

                await supabase
                    .from('academies')
                    .update({columnField: imageUrl})
                    .eq('id', widget.academyId);

                setState(() {
                  academyInfo ??= {};
                  academyInfo?[columnField] = imageUrl;
                });
                setDialogState(() {});

                Get.snackbar(
                  "সফল",
                  "সফলভাবে আপলোড ও আপডেট করা হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  "ত্রুটি",
                  "আপলোড ব্যর্থ হয়েছে: $e",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              } finally {
                setDialogState(() => uploading = false);
              }
            }

            String? logoUrl = academyInfo?['logo_url'];
            String? principalSigUrl = academyInfo?['principal_signature_url'];
            String? accountsSigUrl = academyInfo?['accounts_signature_url'];

            return AlertDialog(
              title: const Text(
                'লগো ও স্বাক্ষর ম্যানেজ করুন',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: uploading
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage:
                                  (logoUrl != null && logoUrl.isNotEmpty)
                                  ? NetworkImage(logoUrl)
                                  : null,
                              child: (logoUrl == null || logoUrl.isEmpty)
                                  ? const Icon(Icons.image, color: Colors.grey)
                                  : null,
                            ),
                            title: const Text('প্রতিষ্ঠানের লগো'),
                            subtitle: Text(
                              logoUrl != null && logoUrl.isNotEmpty
                                  ? 'সংরক্ষিত আছে (পরিবর্তন করতে চাপুন)'
                                  : 'কোনো লগো নেই',
                            ),
                            trailing: const Icon(
                              Icons.upload_file,
                              color: Colors.amber,
                            ),
                            onTap: () => uploadImage('logo_url'),
                          ),
                          const Divider(),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage:
                                  (principalSigUrl != null &&
                                      principalSigUrl.isNotEmpty)
                                  ? NetworkImage(principalSigUrl)
                                  : null,
                              child:
                                  (principalSigUrl == null ||
                                      principalSigUrl.isEmpty)
                                  ? const Icon(Icons.edit, color: Colors.grey)
                                  : null,
                            ),
                            title: const Text('প্রধান শিক্ষকের স্বাক্ষর'),
                            subtitle: Text(
                              principalSigUrl != null &&
                                      principalSigUrl.isNotEmpty
                                  ? 'সংরক্ষিত আছে (পরিবর্তন করতে চাপুন)'
                                  : 'কোনো স্বাক্ষর নেই',
                            ),
                            trailing: const Icon(
                              Icons.upload_file,
                              color: Colors.amber,
                            ),
                            onTap: () => uploadImage('principal_signature_url'),
                          ),
                          const Divider(),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage:
                                  (accountsSigUrl != null &&
                                      accountsSigUrl.isNotEmpty)
                                  ? NetworkImage(accountsSigUrl)
                                  : null,
                              child:
                                  (accountsSigUrl == null ||
                                      accountsSigUrl.isEmpty)
                                  ? const Icon(
                                      Icons.edit_note,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                            title: const Text('পরীক্ষা নিয়ন্ত্রকের স্বাক্ষর'),
                            subtitle: Text(
                              accountsSigUrl != null &&
                                      accountsSigUrl.isNotEmpty
                                  ? 'সংরক্ষিত আছে (পরিবর্তন করতে চাপুন)'
                                  : 'কোনো স্বাক্ষর নেই',
                            ),
                            trailing: const Icon(
                              Icons.upload_file,
                              color: Colors.amber,
                            ),
                            onTap: () => uploadImage('accounts_signature_url'),
                          ),
                        ],
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বন্ধ করুন'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, List<Map<String, String>>>> _fetchAllRoutinesForClass(
    String className,
  ) async {
    Map<String, List<Map<String, String>>> routineMap = {};
    try {
      final response = await supabase
          .from('exam_routines')
          .select('class_name, exam_date, subject_name, exam_time')
          .eq('academy_id', widget.academyId)
          .eq('exam_title', selectedExam ?? '');

      if (response != null) {
        for (var item in (response as List)) {
          String cName = item['class_name']?.toString() ?? '';
          if (cName.isNotEmpty) {
            routineMap.putIfAbsent(cName, () => []).add({
              'date': item['exam_date']?.toString() ?? '',
              'subject': item['subject_name']?.toString() ?? '',
              'time': item['exam_time']?.toString() ?? '',
            });
          }
        }
      }
    } catch (_) {}
    return routineMap;
  }

  Widget _buildAdmitCardWidget(
    Map<String, dynamic> student,
    List<Map<String, String>> routineList,
  ) {
    return _DynamicAdmitCardContent(
      student: student,
      academyInfo: academyInfo,
      selectedExam: selectedExam,
      prefetchedRoutine: routineList,
    );
  }

  void _showAdmitCardDialog(
    BuildContext context,
    Map<String, dynamic> student,
  ) async {
    String className = student['class'] ?? student['class_name'] ?? '';
    List<Map<String, String>> routine = [];
    try {
      final res = await supabase
          .from('exam_routines')
          .select('exam_date, subject_name, exam_time')
          .eq('academy_id', widget.academyId)
          .eq('class_name', className)
          .eq('exam_title', selectedExam ?? '')
          .order('exam_date', ascending: true);
      if (res != null) {
        routine = (res as List)
            .map(
              (e) => {
                'date': e['exam_date']?.toString() ?? '',
                'subject': e['subject_name']?.toString() ?? '',
                'time': e['exam_time']?.toString() ?? '',
              },
            )
            .toList();
      }
    } catch (_) {}

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: _buildAdmitCardWidget(student, routine)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text(
                    'বন্ধ করুন',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateAndShowPdf(Map<String, dynamic> student) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    try {
      String className = student['class'] ?? student['class_name'] ?? '';
      List<Map<String, String>> routine = [];
      final res = await supabase
          .from('exam_routines')
          .select('exam_date, subject_name, exam_time')
          .eq('academy_id', widget.academyId)
          .eq('class_name', className)
          .eq('exam_title', selectedExam ?? '')
          .order('exam_date', ascending: true);
      if (res != null) {
        routine = (res as List)
            .map(
              (e) => {
                'date': e['exam_date']?.toString() ?? '',
                'subject': e['subject_name']?.toString() ?? '',
                'time': e['exam_time']?.toString() ?? '',
              },
            )
            .toList();
      }

      final imageBytes = await _admitCardScreenshotController.captureFromWidget(
        Material(
          color: Colors.transparent,
          child: _buildAdmitCardWidget(student, routine),
        ),
        pixelRatio: 3.0,
      );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Image(pw.MemoryImage(imageBytes), width: 480),
              ),
            );
          },
        ),
      );

      if (mounted) Navigator.pop(context);

      String studentName = student['name'] ?? student['full_name'] ?? 'student';
      String safeFileName = 'AdmitCard_$studentName'
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('$studentName - এডমিট কার্ড'),
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: '$safeFileName.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      Get.snackbar(
        "ত্রুটি",
        "পিডিএফ তৈরি করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _generateAndShowBulkPdf() async {
    List<Map<String, dynamic>> targetStudents =
        groupedStudents[selectedClass] ?? [];

    if (searchQuery.trim().isNotEmpty) {
      String query = searchQuery.toLowerCase().trim();
      targetStudents = targetStudents.where((student) {
        String name = (student['name'] ?? student['full_name'] ?? '')
            .toLowerCase();
        String roll = (student['roll']?.toString() ?? '').toLowerCase();
        String phone = (student['phone'] ?? '').toLowerCase();
        return name.contains(query) ||
            roll.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    if (targetStudents.isEmpty) {
      Get.snackbar(
        "সতর্কতা",
        "ডাউনলোড করার জন্য কোনো শিক্ষার্থী পাওয়া যায়নি!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    ValueNotifier<String> statusTextNotifier = ValueNotifier(
      "রুটিন লোড করা হচ্ছে...",
    );
    bool isCancelled = false; // ক্যানসেল ট্র্যাক করার জন্য ফ্ল্যাগ

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.amber),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: statusTextNotifier,
                  builder: (context, value, child) {
                    return Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.amber.shade800,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "${(value * 100).toStringAsFixed(0)}%",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // ক্যানসেল বাটন
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    isCancelled = true;
                    Navigator.pop(context); // ডায়ালগ বন্ধ করুন
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text(
                    'বাতিল করুন',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      statusTextNotifier.value = "ক্লাসের রুটিন সংগ্রহ করা হচ্ছে...";
      Map<String, List<Map<String, String>>> allClassRoutines =
          await _fetchAllRoutinesForClass(selectedClass);

      if (isCancelled) return; // ক্যানসেল হলে প্রসেস থামিয়ে দিন

      final pdf = pw.Document();
      int total = targetStudents.length;

      for (int i = 0; i < total; i += 2) {
        if (isCancelled) return; // লুপের মধ্যেও ক্যানসেল চেক করা হচ্ছে

        statusTextNotifier.value =
            "এডমিট কার্ড তৈরি হচ্ছে (${i + 1}/$total)...";
        progressNotifier.value = (i + 1) / total;

        final student1 = targetStudents[i];
        String cName1 = student1['class'] ?? student1['class_name'] ?? '';
        List<Map<String, String>> routine1 = allClassRoutines[cName1] ?? [];

        final imageBytes1 = await _admitCardScreenshotController
            .captureFromWidget(
              Material(
                color: Colors.transparent,
                child: _buildAdmitCardWidget(student1, routine1),
              ),
              pixelRatio: 2.5,
            );

        if (isCancelled) return;

        pw.Uint8List? imageBytes2;
        if (i + 1 < total) {
          final student2 = targetStudents[i + 1];
          String cName2 = student2['class'] ?? student2['class_name'] ?? '';
          List<Map<String, String>> routine2 = allClassRoutines[cName2] ?? [];

          imageBytes2 = await _admitCardScreenshotController.captureFromWidget(
            Material(
              color: Colors.transparent,
              child: _buildAdmitCardWidget(student2, routine2),
            ),
            pixelRatio: 2.5,
          );
        }

        if (isCancelled) return;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            build: (pw.Context context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Center(
                    child: pw.Image(pw.MemoryImage(imageBytes1), width: 460),
                  ),
                  if (imageBytes2 != null)
                    pw.Center(
                      child: pw.Image(pw.MemoryImage(imageBytes2), width: 460),
                    ),
                ],
              );
            },
          ),
        );
      }

      if (isCancelled) return;

      if (mounted) Navigator.pop(context); // প্রোগ্রেস ডায়ালগ বন্ধ করুন

      String safeClassName = selectedClass
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');
      String safeFileName = 'AdmitCards_$safeClassName.pdf';

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('$selectedClass - সব এডমিট কার্ড'),
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: safeFileName,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (!isCancelled) {
        Get.snackbar(
          "ত্রুটি",
          "বাল্ক পিডিএফ তৈরি করতে সমস্যা হয়েছে: $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> currentStudents =
        groupedStudents[selectedClass] ?? [];

    if (searchQuery.trim().isNotEmpty) {
      String query = searchQuery.toLowerCase().trim();
      currentStudents = currentStudents.where((student) {
        String name = (student['name'] ?? student['full_name'] ?? '')
            .toLowerCase();
        String roll = (student['roll']?.toString() ?? '').toLowerCase();
        String phone = (student['phone'] ?? '').toLowerCase();
        return name.contains(query) ||
            roll.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.amber.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          InkWell(
            onTap: _showUploadAssetsDialog,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_rounded, size: 20),
                  SizedBox(height: 2),
                  Text(
                    'লগো আপলোড',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _generateAndShowBulkPdf,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_rounded, size: 20),
                  SizedBox(height: 2),
                  Text(
                    'ডাউনলোড',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (examList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedExam,
                    dropdownColor: Colors.amber.shade900,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    items: examList.map((String exam) {
                      return DropdownMenuItem<String>(
                        value: exam,
                        child: Text(
                          exam,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedExam = newValue;
                      });
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(color: Colors.amber.shade800),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              'শিক্ষার্থীর নাম, রোল বা মোবাইল নম্বর দিয়ে খুঁজুন...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.amber.shade800,
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF4F6F9),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 42,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: classList.length,
                          itemBuilder: (context, index) {
                            String className = classList[index];
                            bool isSelected = (className == selectedClass);
                            int count = classCounts[className] ?? 0;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text('$className ($count)'),
                                selected: isSelected,
                                selectedColor: Colors.amber.shade800,
                                backgroundColor: const Color(0xFFF4F6F9),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                onSelected: (bool selected) {
                                  setState(() {
                                    selectedClass = className;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: currentStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 50,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'কোনো শিক্ষার্থী পাওয়া যায়নি!',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: currentStudents.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final student = currentStudents[index];
                            String studentName =
                                student['name'] ??
                                student['full_name'] ??
                                'নামহীন';
                            String roll = student['roll']?.toString() ?? '';
                            String className =
                                student['class'] ??
                                student['class_name'] ??
                                'প্রযোজ্য নয়';
                            String? studentImg = student['image_url'];

                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.amber.shade800,
                                  foregroundColor: Colors.white,
                                  backgroundImage:
                                      (studentImg != null &&
                                          studentImg.isNotEmpty)
                                      ? NetworkImage(studentImg)
                                      : null,
                                  child:
                                      (studentImg == null || studentImg.isEmpty)
                                      ? Text(
                                          roll.isNotEmpty
                                              ? roll
                                              : '${index + 1}',
                                        )
                                      : null,
                                ),
                                title: Text(
                                  studentName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Text(
                                  'শ্রেণি: $className | রোল: ${roll.isNotEmpty ? roll : 'নেই'}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.visibility_rounded,
                                        color: Colors.amber.shade900,
                                      ),
                                      tooltip: 'এডমিট কার্ডের প্রিভিউ দেখুন',
                                      onPressed: () => _showAdmitCardDialog(
                                        context,
                                        student,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        color: Color(0xFF2E7D32),
                                      ),
                                      tooltip: 'পিডিএফ ডাউনলোড করুন',
                                      onPressed: () =>
                                          _generateAndShowPdf(student),
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

class _DynamicAdmitCardContent extends StatelessWidget {
  final Map<String, dynamic> student;
  final Map<String, dynamic>? academyInfo;
  final String? selectedExam;
  final List<Map<String, String>> prefetchedRoutine;

  const _DynamicAdmitCardContent({
    required this.student,
    required this.academyInfo,
    required this.selectedExam,
    required this.prefetchedRoutine,
  });

  @override
  Widget build(BuildContext context) {
    String schoolName =
        academyInfo?['academy_name'] ??
        academyInfo?['name'] ??
        'মাদরাসা/স্কুলের নাম';
    String schoolSubtitle = academyInfo?['address'] ?? 'প্রতিষ্ঠানের ঠিকানা';
    String examName = selectedExam ?? 'বার্ষিক পরীক্ষা';

    String? logoUrl = academyInfo?['logo_url'];
    String? principalSigUrl = academyInfo?['principal_signature_url'];
    String? accountsSigUrl = academyInfo?['accounts_signature_url'];

    String studentName =
        student['name'] ?? student['full_name'] ?? 'নামহীন শিক্ষার্থী';
    String fatherName =
        student['father_name'] ?? student['fathers_name'] ?? 'N/A';
    String roll = student['roll']?.toString() ?? 'N/A';
    String className = student['class'] ?? student['class_name'] ?? 'N/A';
    String group = student['group'] ?? 'সাধারণ';
    String session = student['session'] ?? '২০২৫-২০২৬';

    String principalName = academyInfo?['principal_name'] ?? 'প্রধান শিক্ষক';
    String accountsName = academyInfo?['accounts_name'] ?? 'পরীক্ষা নিয়ন্ত্রক';
    String? imageUrl = student['image_url'];

    const String fallbackAssetPath = 'assets/images/institute logo.png';

    int mid = (prefetchedRoutine.length / 2).ceil();
    List<Map<String, String>> subjectsPart1 = prefetchedRoutine
        .take(mid)
        .toList();
    List<Map<String, String>> subjectsPart2 = prefetchedRoutine
        .skip(mid)
        .toList();

    return Container(
      width: 500,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.red.shade800, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade900, width: 1),
                  image: DecorationImage(
                    image: (logoUrl != null && logoUrl.isNotEmpty)
                        ? NetworkImage(logoUrl) as ImageProvider
                        : const AssetImage(fallbackAssetPath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      schoolName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      schoolSubtitle,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      examName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                        color: Colors.red.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade900, width: 1),
                  image: DecorationImage(
                    image: (logoUrl != null && logoUrl.isNotEmpty)
                        ? NetworkImage(logoUrl) as ImageProvider
                        : const AssetImage(fallbackAssetPath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const Divider(thickness: 1, height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(width: 1, color: Colors.black87),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ADMIT CARD',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('নাম', studentName),
                    _buildInfoRow('পিতার নাম', fatherName),
                    _buildInfoRow('রোল নং', roll),
                    _buildInfoRow('শ্রেণি', className),
                    _buildInfoRow('বিভাগ', group),
                    _buildInfoRow('সেশন', session),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 55,
                height: 68,
                decoration: BoxDecoration(
                  border: Border.all(width: 1),
                  image: (imageUrl != null && imageUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.grey.shade100,
                ),
                child: (imageUrl == null || imageUrl.isEmpty)
                    ? const Center(
                        child: Text('ছবি নেই', style: TextStyle(fontSize: 7.5)),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'পরীক্ষার সময়সূচি:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  color: Colors.black,
                ),
              ),
              Text(
                'সময়: রুটিন অনুযায়ী',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 8.5,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          prefetchedRoutine.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Text(
                      'এই ক্লাসের জন্য কোনো রুটিন পাওয়া যায়নি!',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subjectsPart1.isNotEmpty)
                      Expanded(
                        child: Table(
                          border: TableBorder.all(
                            color: Colors.black54,
                            width: 0.5,
                          ),
                          columnWidths: const {
                            0: FlexColumnWidth(1.2),
                            1: FlexColumnWidth(1.8),
                            2: FlexColumnWidth(1.5),
                          },
                          children: [
                            const TableRow(
                              decoration: BoxDecoration(
                                color: Color(0xFFEEEEEE),
                              ),
                              children: [
                                _TableCellWidget(text: 'তারিখ', isHeader: true),
                                _TableCellWidget(text: 'বিষয়', isHeader: true),
                                _TableCellWidget(text: 'সময়', isHeader: true),
                              ],
                            ),
                            for (var item in subjectsPart1)
                              TableRow(
                                children: [
                                  _TableCellWidget(text: item['date'] ?? ''),
                                  _TableCellWidget(text: item['subject'] ?? ''),
                                  _TableCellWidget(text: item['time'] ?? ''),
                                ],
                              ),
                          ],
                        ),
                      ),
                    if (subjectsPart1.isNotEmpty && subjectsPart2.isNotEmpty)
                      const SizedBox(width: 4),
                    if (subjectsPart2.isNotEmpty)
                      Expanded(
                        child: Table(
                          border: TableBorder.all(
                            color: Colors.black54,
                            width: 0.5,
                          ),
                          columnWidths: const {
                            0: FlexColumnWidth(1.2),
                            1: FlexColumnWidth(1.8),
                            2: FlexColumnWidth(1.5),
                          },
                          children: [
                            const TableRow(
                              decoration: BoxDecoration(
                                color: Color(0xFFEEEEEE),
                              ),
                              children: [
                                _TableCellWidget(text: 'তারিখ', isHeader: true),
                                _TableCellWidget(text: 'বিষয়', isHeader: true),
                                _TableCellWidget(text: 'সময়', isHeader: true),
                              ],
                            ),
                            for (var item in subjectsPart2)
                              TableRow(
                                children: [
                                  _TableCellWidget(text: item['date'] ?? ''),
                                  _TableCellWidget(text: item['subject'] ?? ''),
                                  _TableCellWidget(text: item['time'] ?? ''),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  if (principalSigUrl != null && principalSigUrl.isNotEmpty)
                    SizedBox(
                      height: 20,
                      width: 60,
                      child: Image.network(
                        principalSigUrl,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    const Text(
                      '-----------------------------',
                      style: TextStyle(fontSize: 8.5),
                    ),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: Text(
                      principalName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  if (accountsSigUrl != null && accountsSigUrl.isNotEmpty)
                    SizedBox(
                      height: 20,
                      width: 60,
                      child: Image.network(accountsSigUrl, fit: BoxFit.contain),
                    )
                  else
                    const Text(
                      '-----------------------------',
                      style: TextStyle(fontSize: 8.5),
                    ),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: Text(
                      accountsName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(border: Border.all(width: 0.7)),
            child: const Text(
              'সতর্কবার্তা: পরীক্ষার হলে অবশ্যই এই এডমিট কার্ড সাথে রাখতে হবে। কার্ড ছাড়া পরীক্ষায় অংশগ্রহণ করা যাবে না।',
              style: TextStyle(
                fontSize: 6.5,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 8.5,
                color: Colors.black,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 8.5,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 8.5, color: Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCellWidget extends StatelessWidget {
  final String text;
  final bool isHeader;

  const _TableCellWidget({required this.text, this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isHeader ? 1.5 : 1.2,
        horizontal: 2.0,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.w500,
          fontSize: 6.5,
          color: Colors.black,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
