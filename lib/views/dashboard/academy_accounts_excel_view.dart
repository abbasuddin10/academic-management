import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

class AcademyAccountsExcelView extends StatefulWidget {
  final String academyId;

  const AcademyAccountsExcelView({super.key, required this.academyId});

  @override
  State<AcademyAccountsExcelView> createState() =>
      _AcademyAccountsExcelViewState();
}

class _AcademyAccountsExcelViewState extends State<AcademyAccountsExcelView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isExporting = false;

  String _dateRangeText = '';
  List<Map<String, dynamic>> _accountsList = [];

  double _totalIncomeSum = 0.0;
  double _totalExpenseSum = 0.0;
  double _netBalance = 0.0;

  double _studentFeeTotal = 0.0;
  double _otherIncomeTotal = 0.0;
  double _teacherSalaryTotal = 0.0;
  double _otherExpenseTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchAccountsData();
  }

  Future<void> _fetchAccountsData() async {
    try {
      final now = DateTime.now();
      final List<String> months = [
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

      DateTime startDate = DateTime(now.year, 1, 1, 0, 0, 0);
      DateTime endDate = now;

      _dateRangeText =
          '১ জানুয়ারি ${now.year} থেকে ${endDate.day} ${months[endDate.month - 1]} ${endDate.year}';

      List<Map<String, dynamic>> combinedList = [];
      double totalInc = 0.0;
      double totalExp = 0.0;
      double sFeeTot = 0.0;
      double oIncTot = 0.0;
      double tSalTot = 0.0;
      double oExpTot = 0.0;

      // ১. স্টুডেন্ট ফি কালেকশন (আয়)
      final feeResponse = await supabase
          .from('student_fee_history')
          .select('amount, created_at, month')
          .eq('academy_id', widget.academyId);

      if (feeResponse != null) {
        for (var item in (feeResponse as List)) {
          String dateStr = item['created_at']?.toString() ?? '';
          if (dateStr.isNotEmpty) {
            DateTime? createdAt = DateTime.tryParse(dateStr);
            if (createdAt != null) {
              DateTime localDate = createdAt.toLocal();
              if (localDate.isAfter(
                    startDate.subtract(const Duration(seconds: 1)),
                  ) &&
                  localDate.isBefore(endDate.add(const Duration(seconds: 1)))) {
                double amt =
                    double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                if (amt > 0) {
                  combinedList.add({
                    'date': DateFormat('dd-MM-yyyy').format(localDate),
                    'category': 'ছাত্রছাত্রীর ফি কালেকশন',
                    'type': 'আয়',
                    'amount': amt,
                  });
                  totalInc += amt;
                  sFeeTot += amt;
                }
              }
            }
          }
        }
      }

      // ২. অন্যান্য আয় ও ব্যয় (other_income_expenses টেবিল) - অ্যাডমিন প্যানেলের সাথে সামঞ্জস্যপূর্ণ করা হয়েছে
      try {
        final otherResp = await supabase
            .from('other_income_expenses')
            .select('amount, type, title, created_at')
            .eq('academy_id', widget.academyId);

        if (otherResp != null) {
          for (var item in (otherResp as List)) {
            String dateStr = item['created_at']?.toString() ?? '';
            if (dateStr.isNotEmpty) {
              DateTime? createdAt = DateTime.tryParse(dateStr);
              if (createdAt != null) {
                DateTime localDate = createdAt.toLocal();
                if (localDate.isAfter(
                      startDate.subtract(const Duration(seconds: 1)),
                    ) &&
                    localDate.isBefore(
                      endDate.add(const Duration(seconds: 1)),
                    )) {
                  double amt =
                      double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                  String type =
                      item['type']?.toString().toLowerCase().trim() ?? '';
                  String title = item['title']?.toString() ?? 'অন্যান্য';
                  String formattedDate = DateFormat(
                    'dd-MM-yyyy',
                  ).format(localDate);

                  if (type == 'income' || type == 'আয়' || type == 'آئ') {
                    combinedList.add({
                      'date': formattedDate,
                      'category': 'অন্যান্য আয় ($title)',
                      'type': 'আয়',
                      'amount': amt,
                    });
                    totalInc += amt;
                    oIncTot += amt;
                  } else if (type == 'expense' ||
                      type == 'ব্যয়' ||
                      type == 'cost') {
                    combinedList.add({
                      'date': formattedDate,
                      'category': 'অন্যান্য ব্যয় ($title)',
                      'type': 'ব্যয়',
                      'amount': amt,
                    });
                    totalExp += amt;
                    oExpTot += amt;
                  }
                }
              }
            }
          }
        }
      } catch (e) {}

      // ৩. ছাত্রছাত্রীদের অন্যান্য কালেকশন (student_other_collections টেবিল)
      try {
        final studentOtherResponse = await supabase
            .from('student_other_collections')
            .select('amount, payment_date, created_at')
            .eq('academy_id', widget.academyId);

        if (studentOtherResponse != null) {
          for (var item in (studentOtherResponse as List)) {
            String dateStr =
                item['payment_date'] ?? item['created_at']?.toString() ?? '';
            if (dateStr.isNotEmpty) {
              DateTime? createdAt = DateTime.tryParse(dateStr);
              if (createdAt != null) {
                DateTime localDate = createdAt.toLocal();
                if (localDate.isAfter(
                      startDate.subtract(const Duration(seconds: 1)),
                    ) &&
                    localDate.isBefore(
                      endDate.add(const Duration(seconds: 1)),
                    )) {
                  double amt =
                      double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                  if (amt > 0) {
                    combinedList.add({
                      'date': DateFormat('dd-MM-yyyy').format(localDate),
                      'category': 'অন্যান্য আয় (ছাত্র কালেকশন)',
                      'type': 'আয়',
                      'amount': amt,
                    });
                    totalInc += amt;
                    oIncTot += amt;
                  }
                }
              }
            }
          }
        }
      } catch (e) {}

      // ৪. শিক্ষক বেতন পরিশোধ (ব্যয়)
      try {
        final salaryResp = await supabase
            .from('teacher_salary_history')
            .select('amount, created_at, month')
            .eq('academy_id', widget.academyId);

        if (salaryResp != null) {
          for (var item in (salaryResp as List)) {
            String dateStr = item['created_at']?.toString() ?? '';
            if (dateStr.isNotEmpty) {
              DateTime? createdAt = DateTime.tryParse(dateStr);
              if (createdAt != null) {
                DateTime localDate = createdAt.toLocal();
                if (localDate.isAfter(
                      startDate.subtract(const Duration(seconds: 1)),
                    ) &&
                    localDate.isBefore(
                      endDate.add(const Duration(seconds: 1)),
                    )) {
                  double amt =
                      double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                  String month = item['month']?.toString() ?? '';
                  if (amt > 0) {
                    combinedList.add({
                      'date': DateFormat('dd-MM-yyyy').format(localDate),
                      'category': 'শিক্ষক বেতন পরিশোধ ($month)',
                      'type': 'ব্যয়',
                      'amount': amt,
                    });
                    totalExp += amt;
                    tSalTot += amt;
                  }
                }
              }
            }
          }
        }
      } catch (e) {}

      setState(() {
        _accountsList = combinedList;
        _totalIncomeSum = totalInc;
        _totalExpenseSum = totalExp;
        _netBalance = totalInc - totalExp;
        _studentFeeTotal = sFeeTot;
        _otherIncomeTotal = oIncTot;
        _teacherSalaryTotal = tSalTot;
        _otherExpenseTotal = oExpTot;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportToExcel() async {
    if (_accountsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('রপ্তানি করার মতো কোনো হিসাব নেই!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      var excel = excel_lib.Excel.createExcel();
      String? defaultSheet = excel.getDefaultSheet();
      var sheet = excel[defaultSheet ?? 'Sheet1'];
      excel.rename(defaultSheet ?? 'Sheet1', 'Academy Accounts');
      sheet = excel['Academy Accounts'];

      // ১. প্রফেশনাল টাইটেল ও সময়সীমা হেডার
      sheet.appendRow([
        excel_lib.TextCellValue('========================================='),
      ]);
      sheet.appendRow([
        excel_lib.TextCellValue('       ACADEMY FINANCIAL REPORT       '),
      ]);
      sheet.appendRow([
        excel_lib.TextCellValue('হিসাবের সময়সীমা: $_dateRangeText'),
      ]);
      sheet.appendRow([
        excel_lib.TextCellValue('========================================='),
      ]);
      sheet.appendRow([]); // খালি সারি

      // ২. টেবিল হেডার
      sheet.appendRow([
        excel_lib.TextCellValue('তারিখ'),
        excel_lib.TextCellValue('খাত / বিবরণ'),
        excel_lib.TextCellValue('ধরন (আয়/ব্যয়)'),
        excel_lib.TextCellValue('টাকার পরিমাণ (৳)'),
      ]);

      // হেডার রো ডিজাইন (বোল্ড ও টিল কালার)
      for (int i = 0; i < 4; i++) {
        var cell = sheet.cell(
          excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5),
        );
        cell.cellStyle = excel_lib.CellStyle(
          bold: true,
          fontColorHex: excel_lib.ExcelColor.fromHexString('#FFFFFF'),
          backgroundColorHex: excel_lib.ExcelColor.fromHexString('#008080'),
          horizontalAlign: excel_lib.HorizontalAlign.Center,
        );
      }

      // ৩. ডাটা রো যুক্ত করা
      int rowIndex = 6;
      for (var item in _accountsList) {
        sheet
            .cell(
              excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 0,
                rowIndex: rowIndex,
              ),
            )
            .value = excel_lib.TextCellValue(
          item['date'],
        );
        sheet
            .cell(
              excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 1,
                rowIndex: rowIndex,
              ),
            )
            .value = excel_lib.TextCellValue(
          item['category'],
        );
        sheet
            .cell(
              excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 2,
                rowIndex: rowIndex,
              ),
            )
            .value = excel_lib.TextCellValue(
          item['type'],
        );
        sheet
            .cell(
              excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 3,
                rowIndex: rowIndex,
              ),
            )
            .value = excel_lib.DoubleCellValue(
          item['amount'],
        );
        rowIndex++;
      }

      // ৪. অটো সামারি ও সেক্টরভিত্তিক হিসাব এক্সেলে যুক্ত করা
      rowIndex += 2;
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.TextCellValue(
        '--- সেক্টরভিত্তিক সারসংক্ষেপ ---',
      );

      rowIndex++;
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.TextCellValue(
        '• ছাত্রছাত্রী ফি মোট:',
      );
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _studentFeeTotal,
      );

      rowIndex++;
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.TextCellValue(
        '• অন্যান্য আয় মোট:',
      );
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _otherIncomeTotal,
      );

      rowIndex++;
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.TextCellValue(
        '• শিক্ষক বেতন পরিশোধ মোট:',
      );
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _teacherSalaryTotal,
      );

      rowIndex++;
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.TextCellValue(
        '• অন্যান্য খরচ মোট:',
      );
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _otherExpenseTotal,
      );

      rowIndex += 2;
      var incCell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
          columnIndex: 1,
          rowIndex: rowIndex,
        ),
      );
      incCell.value = excel_lib.TextCellValue('সর্বমোট আয়:');
      incCell.cellStyle = excel_lib.CellStyle(bold: true);
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _totalIncomeSum,
      );

      rowIndex++;
      var expCell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
          columnIndex: 1,
          rowIndex: rowIndex,
        ),
      );
      expCell.value = excel_lib.TextCellValue('সর্বমোট ব্যয়:');
      expCell.cellStyle = excel_lib.CellStyle(bold: true);
      sheet
          .cell(
            excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ),
          )
          .value = excel_lib.DoubleCellValue(
        _totalExpenseSum,
      );

      rowIndex++;
      var netTitle = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
          columnIndex: 1,
          rowIndex: rowIndex,
        ),
      );
      netTitle.value = excel_lib.TextCellValue('নিট ক্যাশ ব্যালেন্স:');
      netTitle.cellStyle = excel_lib.CellStyle(
        bold: true,
        fontColorHex: excel_lib.ExcelColor.fromHexString('#000080'),
      );

      var netVal = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
          columnIndex: 3,
          rowIndex: rowIndex,
        ),
      );
      netVal.value = excel_lib.DoubleCellValue(_netBalance);
      netVal.cellStyle = excel_lib.CellStyle(
        bold: true,
        fontColorHex: excel_lib.ExcelColor.fromHexString('#000080'),
      );

      var fileBytes = excel.save();
      if (fileBytes != null) {
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!directory.existsSync()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final String formattedDate = DateFormat(
          'dd-MM-yyyy',
        ).format(DateTime.now());
        final String fileName = 'একাডেমি_হিসাব_$formattedDate.xlsx';
        final path = '${directory!.path}/$fileName';

        File file = File(path);
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('এক্সেল ফাইল সেভ হয়েছে: Download/$fileName'),
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
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('একাডেমি হিসাব ও এক্সেল'),
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      'হিসাবের সময়সীমা: $_dateRangeText',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: Colors.green.shade50,
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              children: [
                                const Text(
                                  'মোট আয়',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '৳ ${_totalIncomeSum.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Card(
                          color: Colors.red.shade50,
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              children: [
                                const Text(
                                  'মোট ব্যয়',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '৳ ${_totalExpenseSum.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Card(
                          color: Colors.indigo.shade50,
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              children: [
                                const Text(
                                  'নিট ব্যালেন্স',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '৳ ${_netBalance.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),

                  const Text(
                    'খাতভিত্তিক সারসংক্ষেপ (জানুয়ারি থেকে রানিং)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      _buildSectorCard(
                        'ছাত্রছাত্রী ফি',
                        _studentFeeTotal,
                        Icons.groups,
                        Colors.blue,
                      ),
                      _buildSectorCard(
                        'অন্যান্য আয়',
                        _otherIncomeTotal,
                        Icons.monetization_on,
                        Colors.teal,
                      ),
                      _buildSectorCard(
                        'শিক্ষক বেতন',
                        _teacherSalaryTotal,
                        Icons.payments,
                        Colors.orange,
                      ),
                      _buildSectorCard(
                        'অন্যান্য খরচ',
                        _otherExpenseTotal,
                        Icons.money_off,
                        Colors.redAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'সকল লেনদেনের তালিকা',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),

                  _accountsList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text(
                              'কোনো হিসাব পাওয়া যায়নি।',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _accountsList.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            final item = _accountsList[index];
                            bool isIncome = item['type'] == 'আয়';
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isIncome
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  child: Icon(
                                    isIncome
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    color: isIncome ? Colors.green : Colors.red,
                                  ),
                                ),
                                title: Text(
                                  item['category'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'তারিখ: ${item['date']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                trailing: Text(
                                  '${isIncome ? '+' : '-'} ৳ ${item['amount'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isIncome ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectorCard(
    String title,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '৳ ${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
