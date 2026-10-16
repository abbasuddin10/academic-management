import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

class StudentsFileDownloadView extends StatefulWidget {
  final String academyId;

  const StudentsFileDownloadView({super.key, required this.academyId});

  @override
  State<StudentsFileDownloadView> createState() =>
      _StudentsFileDownloadViewState();
}

class _StudentsFileDownloadViewState extends State<StudentsFileDownloadView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _studentsList = [];
  String _selectedClass = 'সব ক্লাস';
  List<String> _classes = ['সব ক্লাস'];
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final response = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', widget.academyId);

      final List list = response as List;
      _studentsList = list.map((e) => Map<String, dynamic>.from(e)).toList();

      Set<String> classSet = {'সব ক্লাস'};
      for (var student in _studentsList) {
        String className =
            student['class']?.toString().trim() ??
            student['class_name']?.toString().trim() ??
            'অন্যান্য';
        if (className.isNotEmpty) {
          classSet.add(className);
        }
      }
      _classes = classSet.toList();
      _classes.sort();
      _classes.remove('সব ক্লাস');
      _classes.insert(0, 'সব ক্লাস');
        } catch (e) {
      // Error handling
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatHeaderName(String key) {
    switch (key.toLowerCase()) {
      case 'full_name':
      case 'name':
        return 'শিক্ষার্থীর নাম';
      case 'father_name':
      case 'guardian_name':
        return 'পিতার নাম';
      case 'mother_name':
        return 'মাতার নাম';
      case 'class':
      case 'class_name':
        return 'শ্রেণি';
      case 'roll':
        return 'রোল';
      case 'phone':
      case 'mobile':
        return 'মোবাইল নাম্বার';
      case 'monthly_fee':
        return 'মাসিক ফি';
      case 'gender':
        return 'লিঙ্গ';
      case 'address':
        return 'ঠিকানা';
      case 'id':
        return 'আইডি';
      case 'academy_id':
        return 'একাডেমি আইডি';
      case 'created_at':
        return 'সংযুক্তির তারিখ';
      case 'image_url':
        return 'ছবির লিংক';
      default:
        return key.replaceAll('_', ' ').capitalizeFirst ?? key;
    }
  }

  Future<void> _exportToExcel() async {
    if (_studentsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('রপ্তানি করার মতো কোনো শিক্ষার্থী নেই!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      var excel = excel_lib.Excel.createExcel();
      String? defaultSheet = excel.getDefaultSheet();
      var sheet = excel[defaultSheet ?? 'Sheet1'];
      excel.rename(defaultSheet ?? 'Sheet1', 'Students List');
      sheet = excel['Students List'];

      List<Map<String, dynamic>> exportData = _selectedClass == 'সব ক্লাস'
          ? _studentsList
          : _studentsList.where((s) {
              String c =
                  s['class']?.toString() ?? s['class_name']?.toString() ?? '';
              return c == _selectedClass;
            }).toList();

      if (exportData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('এই শ্রেণিতে কোনো শিক্ষার্থী নেই!'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isExporting = false);
        return;
      }

      // সুপাবেসের প্রথম রেকর্ড থেকে সমস্ত কলামের নাম নেওয়া
      List<String> columns = exportData.first.keys.toList();

      // ১. হেডার রো তৈরি এবং স্টাইলিং (বোল্ড ও ব্যাকগ্রাউন্ড কালার)
      for (int colIndex = 0; colIndex < columns.length; colIndex++) {
        var cell = sheet.cell(
          excel_lib.CellIndex.indexByColumnRow(
            columnIndex: colIndex,
            rowIndex: 0,
          ),
        );
        cell.value = excel_lib.TextCellValue(
          _formatHeaderName(columns[colIndex]),
        );
        cell.cellStyle = excel_lib.CellStyle(
          bold: true,
          fontColorHex: excel_lib.ExcelColor.fromHexString('#FFFFFF'),
          backgroundColorHex: excel_lib.ExcelColor.fromHexString('#008080'),
          horizontalAlign: excel_lib.HorizontalAlign.Center,
        );
      }

      // ২. শিক্ষার্থীদের সকল তথ্য সেল বাই সেল রো আকারে যুক্ত করা
      for (int rowIndex = 0; rowIndex < exportData.length; rowIndex++) {
        var student = exportData[rowIndex];
        for (int colIndex = 0; colIndex < columns.length; colIndex++) {
          String val = student[columns[colIndex]]?.toString() ?? '';
          var cell = sheet.cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: colIndex,
              rowIndex: rowIndex + 1, // 헤ডার রো এর পর থেকে ডেটা শুরু হবে
            ),
          );
          cell.value = excel_lib.TextCellValue(val);
        }
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        // মোবাইলের পাবলিক ডাউনলোড ফোল্ডারে সেভ করার পাথ
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final String formattedDate = DateFormat(
          'dd-MM-yyyy',
        ).format(DateTime.now());
        final String fileName = 'স্টুডেন্ট_লিস্ট_$formattedDate.xlsx';
        final path = '${directory!.path}/$fileName';

        File file = File(path);
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ফাইলটি সফলভাবে সেভ হয়েছে: Download/$fileName'),
              backgroundColor: Colors.green,
            ),
          );
        }

        await OpenFilex.open(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('এক্সেল তৈরি করতে সমস্যা হয়েছে: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredList = _selectedClass == 'সব ক্লাস'
        ? _studentsList
        : _studentsList.where((s) {
            String c =
                s['class']?.toString() ?? s['class_name']?.toString() ?? '';
            return c == _selectedClass;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ছাত্রছাত্রীদের তালিকা ও এক্সেল'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download),
            tooltip: 'এক্সেল ডাউনলোড করুন',
            onPressed: _isExporting ? null : _exportToExcel,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
              children: [
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      String className = _classes[index];
                      bool isSelected = (className == _selectedClass);
                      int count = className == 'সব ক্লাস'
                          ? _studentsList.length
                          : _studentsList.where((s) {
                              String c =
                                  s['class']?.toString() ??
                                  s['class_name']?.toString() ??
                                  '';
                              return c == className;
                            }).length;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text('$className ($count)'),
                          selected: isSelected,
                          selectedColor: Colors.teal,
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
                const Divider(height: 1),
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো শিক্ষার্থী পাওয়া যায়নি।',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredList.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final student = filteredList[index];
                            String name =
                                student['full_name'] ??
                                student['name'] ??
                                'নামহীন শিক্ষার্থী';
                            String fatherName =
                                student['father_name'] ??
                                student['guardian_name'] ??
                                'তথ্য নেই';
                            String className =
                                student['class'] ??
                                student['class_name'] ??
                                'শ্রেণি নেই';
                            String roll = student['roll']?.toString() ?? 'নেই';
                            String phone =
                                student['phone'] ??
                                student['mobile'] ??
                                'নম্বর নেই';
                            String fee =
                                student['monthly_fee']?.toString() ?? '0';
                            String? imageUrl = student['image_url'];

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.teal.shade100,
                                      backgroundImage:
                                          (imageUrl != null &&
                                              imageUrl.isNotEmpty)
                                          ? NetworkImage(imageUrl)
                                          : null,
                                      child:
                                          (imageUrl == null || imageUrl.isEmpty)
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.teal,
                                              size: 28,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'পিতা: $fatherName',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                'ক্লাস: $className',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.teal.shade800,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'রোল: $roll',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'মোবাইল: $phone',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'মাসিক ফি',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          '৳ $fee',
                                          style: const TextStyle(
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
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
              ],
            ),
    );
  }
}

extension StringExtension on String {
  String get capitalizeFirst {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
