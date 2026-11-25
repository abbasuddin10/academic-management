import 'package:academy_management/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TotalCollectedDetailsView extends StatefulWidget {
  final String academyId;
  final String dateRange;

  const TotalCollectedDetailsView({
    super.key,
    required this.academyId,
    required this.dateRange,
  });

  @override
  State<TotalCollectedDetailsView> createState() =>
      _TotalCollectedDetailsViewState();
}

class _TotalCollectedDetailsViewState extends State<TotalCollectedDetailsView> {
  String selectedMonthFilter = 'সব মাস';
  String selectedClassFilter = 'সব শ্রেণি';
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchStudentFeeStatus() async {
    final supabase = Supabase.instance.client;

    final studentsResponse = await supabase
        .from('students')
        .select('*')
        .eq('academy_id', widget.academyId);

    List studentsList = studentsResponse as List;

    final feeHistoryResponse = await supabase
        .from('student_fee_history')
        .select('*')
        .eq('academy_id', widget.academyId);

    List feeHistoryList = feeHistoryResponse as List;

    Map<String, Set<String>> studentPaidNormalizedMap = {};
    Map<String, List<Map<String, dynamic>>> studentFeeDetailsMap = {};
    Set<String> uniqueMonths = {};
    Set<String> uniqueClasses = {};

    for (var item in feeHistoryList) {
      String studentId = item['student_id']?.toString() ?? '';
      String originalMonth = item['month']?.toString().trim() ?? '';
      var amount = item['amount'] ?? item['fee_amount'] ?? item['total'] ?? 0;

      if (studentId.isNotEmpty && originalMonth.isNotEmpty) {
        uniqueMonths.add(originalMonth);

        studentFeeDetailsMap.putIfAbsent(studentId, () => []);
        studentFeeDetailsMap[studentId]!.add({
          'month': originalMonth,
          'amount': amount,
        });

        studentPaidNormalizedMap.putIfAbsent(studentId, () => {});
        String cleanMonth = originalMonth
            .replaceAll(RegExp(r'[0-9]'), '')
            .replaceAll(' ', '')
            .toLowerCase();
        studentPaidNormalizedMap[studentId]!.add(cleanMonth);
      }
    }

    List<String> standardMonths = [
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

    final now = DateTime.now();
    int currentMonthIndex = now.month - 1;
    List<String> applicableMonths = standardMonths.sublist(
      0,
      currentMonthIndex + 1,
    );

    List<Map<String, dynamic>> processedStudents = [];

    for (var student in studentsList) {
      String sId = student['id']?.toString() ?? '';
      String name =
          student['name'] ?? student['full_name'] ?? 'নামহীন শিক্ষার্থী';
      String roll = student['roll']?.toString() ?? 'N/A';
      String studentClass = student['class']?.toString() ?? 'N/A';
      String phone = student['phone'] ?? student['mobile'] ?? 'প্রযোজ্য নয়';
      String fatherName = student['father_name']?.toString().trim() ?? '';
      String profileImage = student['image_url']?.toString().trim() ?? '';
      double monthlyFee =
          double.tryParse(student['monthly_fee']?.toString() ?? '0') ?? 0.0;

      if (studentClass != 'N/A' && studentClass.isNotEmpty) {
        uniqueClasses.add(studentClass);
      }

      List<Map<String, dynamic>> feeDetails = studentFeeDetailsMap[sId] ?? [];
      Set<String> paidNormalized = studentPaidNormalizedMap[sId] ?? {};

      List<String> dueMonths = applicableMonths.where((m) {
        String cleanStandard = m.replaceAll(' ', '').toLowerCase();
        bool isPaid = paidNormalized.any(
          (paid) => paid.contains(cleanStandard),
        );
        return !isPaid;
      }).toList();

      double totalDueAmount = dueMonths.length * monthlyFee;

      processedStudents.add({
        'name': name,
        'roll': roll,
        'class': studentClass,
        'phone': phone,
        'father_name': fatherName,
        'profile_image': profileImage,
        'monthly_fee': monthlyFee,
        'fee_details': feeDetails,
        'due_months': dueMonths,
        'total_due_amount': totalDueAmount,
      });
    }

    List<Map<String, dynamic>> filteredList = processedStudents;

    if (selectedClassFilter != 'সব শ্রেণি') {
      filteredList = filteredList.where((student) {
        bool isTargetClass =
            student['class'].toString().trim().toLowerCase() ==
            selectedClassFilter.trim().toLowerCase();
        List due = student['due_months'];
        return isTargetClass && due.isNotEmpty;
      }).toList();
    }

    if (selectedMonthFilter != 'সব মাস') {
      filteredList = filteredList.where((student) {
        List<Map<String, dynamic>> details = List<Map<String, dynamic>>.from(
          student['fee_details'],
        );
        return details.any(
          (d) => d['month'].toString().contains(selectedMonthFilter),
        );
      }).toList();
    }

    if (searchQuery.isNotEmpty) {
      String query = searchQuery.toLowerCase();
      filteredList = filteredList.where((student) {
        String name = student['name'].toString().toLowerCase();
        String roll = student['roll'].toString().toLowerCase();
        return name.contains(query) || roll.contains(query);
      }).toList();
    }

    // নির্বাচিত মাসের মোট সংগৃহীত টাকা হিসাব করা
    double totalCollectedAmount = 0.0;
    if (selectedMonthFilter != 'সব মাস') {
      for (var student in filteredList) {
        List<Map<String, dynamic>> details = List<Map<String, dynamic>>.from(
          student['fee_details'],
        );
        for (var d in details) {
          if (d['month'].toString().contains(selectedMonthFilter)) {
            double amt = double.tryParse(d['amount']?.toString() ?? '0') ?? 0.0;
            totalCollectedAmount += amt;
          }
        }
      }
    } else {
      for (var student in filteredList) {
        List<Map<String, dynamic>> details = List<Map<String, dynamic>>.from(
          student['fee_details'],
        );
        for (var d in details) {
          double amt = double.tryParse(d['amount']?.toString() ?? '0') ?? 0.0;
          totalCollectedAmount += amt;
        }
      }
    }

    return {
      'list': filteredList,
      'months': ['সব মাস', ...uniqueMonths],
      'classes': ['সব শ্রেণি', ...uniqueClasses],
      'total_collected': totalCollectedAmount,
    };
  }

  void _showFeeDetailsPopup(
    BuildContext context,
    Map<String, dynamic> student,
  ) {
    List<Map<String, dynamic>> feeDetails = List<Map<String, dynamic>>.from(
      student['fee_details'] ?? [],
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student['name'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'রোল: ${student['roll']} | শ্রেণি: ${student['class']}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const Divider(),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: feeDetails.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'কোনো পরিশোধিত ফি পাওয়া যায়নি।',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: feeDetails.length,
                    itemBuilder: (context, index) {
                      final item = feeDetails[index];
                      return Container(
                        margin: EdgeInsets.symmetric(vertical: 4),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.tileOf(context, Colors.green),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.tileOf(context, Colors.green)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_month,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'মাস: ${item['month']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.inkOf(context),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '৳ ${item['amount']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'বন্ধ করুন',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('শিক্ষার্থীর ফি তালিকা'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchStudentFeeStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('ত্রুটি: ${snapshot.error}'));
          }

          final data = snapshot.data ?? {};
          final List<Map<String, dynamic>> list = data['list'] ?? [];
          final List<String> availableMonths = List<String>.from(
            data['months'] ?? ['সব মাস'],
          );
          final List<String> availableClasses = List<String>.from(
            data['classes'] ?? ['সব শ্রেণি'],
          );
          final double totalCollected = data['total_collected'] ?? 0.0;

          return Column(
            children: [
              // ফিল্টার ও সার্চ প্যানেল
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.tileOf(context, Colors.teal),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.tileOf(context, Colors.teal)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedClassFilter,
                                dropdownColor: Colors.white,
                                isExpanded: true,
                                style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                icon: Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.teal,
                                ),
                                items: availableClasses.map((String cls) {
                                  return DropdownMenuItem<String>(
                                    value: cls,
                                    child: Text(
                                      cls,
                                      style: TextStyle(
                                        color: AppTheme.inkOf(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      selectedClassFilter = newValue;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.tileOf(context, Colors.green),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.tileOf(context, Colors.green)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedMonthFilter,
                                dropdownColor: Colors.white,
                                isExpanded: true,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                icon: Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.green,
                                ),
                                items: availableMonths.map((String month) {
                                  return DropdownMenuItem<String>(
                                    value: month,
                                    child: Text(
                                      month,
                                      style: TextStyle(
                                        color: AppTheme.inkOf(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      selectedMonthFilter = newValue;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'নাম বা রোল লিখে খুঁজুন...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedOf(context),
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          size: 16,
                                          color: AppTheme.mutedOf(context),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                            searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppTheme.altSurfaceOf(context),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 0,
                                  horizontal: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              setState(() {
                                searchQuery = _searchController.text.trim();
                              });
                            },
                            child: const Text(
                              'সার্চ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // নির্বাচিত মাসের মোট কালেকশন দেখানোর কার্ড (নতুন যুক্ত করা হয়েছে)
              Container(
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(12, 10, 12, 0),
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.tileOf(context, Colors.green),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.tileOf(context, Colors.green)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedMonthFilter == 'সব মাস'
                          ? 'সর্বমোট সংগ্রহ:'
                          : '$selectedMonthFilter মাসের মোট সংগ্রহ:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                    Text(
                      '৳ ${totalCollected.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

              // স্টুডেন্ট লিস্ট
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 60,
                              color: AppTheme.tileOf(context, Colors.green),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'এই মুহূর্তে কোনো বকেয়া নেই!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.mutedOf(context),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          final student = list[index];
                          List<String> due = List<String>.from(
                            student['due_months'],
                          );
                          String fatherName = student['father_name'];
                          String profileImage = student['profile_image'];
                          double totalDueAmount = student['total_due_amount'];

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () =>
                                  _showFeeDetailsPopup(context, student),
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor:
                                              AppTheme.tileOf(context, Colors.green),
                                          backgroundImage:
                                              profileImage.isNotEmpty
                                              ? NetworkImage(profileImage)
                                              : null,
                                          child: profileImage.isEmpty
                                              ? const Icon(
                                                  Icons.person,
                                                  color: Colors.green,
                                                  size: 24,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                student['name'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: AppTheme.inkOf(context),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'বাবার নাম: ${fatherName.isEmpty ? 'প্রযোজ্য নয়' : fatherName}',
                                                style: TextStyle(
                                                  color: AppTheme.mutedOf(context),
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                'ফোন: ${student['phone']}',
                                                style: TextStyle(
                                                  color: AppTheme.mutedOf(context),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'রোল: ${student['roll']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppTheme.inkOf(context),
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              '${student['class']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppTheme.inkOf(context),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'বাকিঃ ${totalDueAmount.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: due.isNotEmpty
                                                    ? Colors.red
                                                    : Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        color: Color(0xFFEEEEEE),
                                      ),
                                    ),
                                    Text(
                                      'বকেয়া মাস: ${due.isEmpty ? 'পরিশোধিত' : due.join(', ')}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.inkOf(context),
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
