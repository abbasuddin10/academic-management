import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcademyTeachersSalaryView extends StatefulWidget {
  final String academyId;
  final bool
  isReadOnly; // শুধু দেখার জন্য নাকি পেমেন্ট করার জন্য, তা নির্ধারণ করতে

  const AcademyTeachersSalaryView({
    super.key,
    required this.academyId,
    this.isReadOnly =
        false, // ডিফল্টভাবে ফলস (অর্থাৎ সুপার অ্যাডমিন ফুল এক্সেস পাবে)
  });

  @override
  State<AcademyTeachersSalaryView> createState() =>
      _AcademyTeachersSalaryViewState();
}

class _AcademyTeachersSalaryViewState extends State<AcademyTeachersSalaryView> {
  final supabase = Supabase.instance.client;

  // ব্যাকগ্রাউন্ডে ডেটা লোড করার জন্য এবং সার্চ কন্ট্রোলার
  List<Map<String, dynamic>> _allTeachersAndStaff = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchTeachersAndStaffInBackground();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ব্যাকগ্রাউন্ডে ডেটা ফেচ করার ফাংশন (পুরো পেজ রিফ্রেশ বা আটকে রাখবে না)
  Future<void> _fetchTeachersAndStaffInBackground() async {
    try {
      final response = await supabase
          .from('users')
          .select()
          .eq('academy_id', widget.academyId)
          .inFilter('role', ['teacher', 'super_admin', 'staff']);

      if (mounted) {
        setState(() {
          _allTeachersAndStaff = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // শিক্ষকের বকেয়া বা অগ্রিমের হিসাব বের করার স্মার্ট ফাংশন
  Future<Map<String, dynamic>> _calculateTeacherDue(
    String teacherId,
    double monthlySalary,
  ) async {
    try {
      final userResponse = await supabase
          .from('users')
          .select('created_at')
          .eq('id', teacherId)
          .maybeSingle();

      if (userResponse == null || userResponse['created_at'] == null) {
        return {'due': 0.0, 'totalPayable': 0.0, 'totalPaid': 0.0};
      }

      DateTime createdAt = DateTime.parse(userResponse['created_at']);
      DateTime now = DateTime.now();

      int totalMonths =
          (now.year - createdAt.year) * 12 + now.month - createdAt.month + 1;
      if (totalMonths < 1) totalMonths = 1;

      double totalPayableSalary = totalMonths * monthlySalary;

      final historyResponse = await supabase
          .from('teacher_salary_history')
          .select('amount')
          .eq('teacher_id', teacherId)
          .eq('academy_id', widget.academyId);

      double totalPaid = 0.0;
      if (historyResponse != null) {
        for (var item in (historyResponse as List)) {
          double amt =
              double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
          totalPaid += amt;
        }
      }

      double due = totalPayableSalary - totalPaid;
      if (due < 0) due = 0;

      return {
        'due': due,
        'totalPayable': totalPayableSalary,
        'totalPaid': totalPaid,
      };
    } catch (e) {
      return {'due': 0.0, 'totalPayable': 0.0, 'totalPaid': 0.0};
    }
  }

  // পেমেন্ট যোগ করার ডায়ালগ বক্স
  void _showAddSalaryDialog(Map<String, dynamic> teacher) {
    if (widget.isReadOnly) return;

    final TextEditingController amountController = TextEditingController();
    String selectedMonth = 'জানুয়ারি';
    int selectedYear = DateTime.now().year;

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

    final TextEditingController dateController = TextEditingController();
    DateTime? selectedDateObj = DateTime.now();
    dateController.text =
        "${selectedDateObj.day} ${months[selectedDateObj.month - 1]} ${selectedDateObj.year}";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${teacher['full_name']} - এর বেতন প্রদান'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: selectedMonth,
                            decoration: const InputDecoration(labelText: 'মাস'),
                            items: months.map((String month) {
                              return DropdownMenuItem<String>(
                                value: month,
                                child: Text(month),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setDialogState(() {
                                  selectedMonth = newValue;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<int>(
                            value: selectedYear,
                            decoration: const InputDecoration(labelText: 'বছর'),
                            items:
                                List.generate(
                                  5,
                                  (index) => DateTime.now().year - 2 + index,
                                ).map((int year) {
                                  return DropdownMenuItem<int>(
                                    value: year,
                                    child: Text(year.toString()),
                                  );
                                }).toList(),
                            onChanged: (int? newValue) {
                              if (newValue != null) {
                                setDialogState(() {
                                  selectedYear = newValue;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'প্রদানের তারিখ',
                        suffixIcon: Icon(
                          Icons.calendar_today,
                          color: Colors.teal,
                        ),
                      ),
                      onTap: () async {
                        final DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDateObj ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          setDialogState(() {
                            selectedDateObj = pickedDate;
                            dateController.text =
                                "${pickedDate.day} ${months[pickedDate.month - 1]} ${pickedDate.year}";
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'টাকার পরিমাণ (যেমন: ১৫০০০)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বাতিল'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final monthString = '$selectedMonth $selectedYear';
                    final date = dateController.text.trim();
                    final amount =
                        double.tryParse(amountController.text.trim()) ?? 0.0;

                    if (date.isEmpty || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('সব তথ্য সঠিকভাবে পূরণ করুন!'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      await supabase.from('teacher_salary_history').insert({
                        'teacher_id': teacher['id'],
                        'academy_id': widget.academyId,
                        'month': monthString,
                        'payment_date': date,
                        'amount': amount,
                      });

                      Navigator.pop(context);
                      // ব্যাকগ্রাউন্ডে আবার ডেটা আপডেট করে নেওয়া
                      _fetchTeachersAndStaffInBackground();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'বেতনের হিসাব সফলভাবে আপডেট করা হয়েছে!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('ডাটা সেভ করতে সমস্যা হয়েছে: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('সংরক্ষণ করুন'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // পূর্ববর্তী সকল বেতনের ইতিহাস দেখার পপআপ
  void _showAllSalaryHistory(Map<String, dynamic> teacher) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${teacher['full_name']} - এর সকল বেতনের ইতিহাস',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.teal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: supabase
                          .from('teacher_salary_history')
                          .select()
                          .eq('teacher_id', teacher['id'])
                          .eq('academy_id', widget.academyId)
                          .order('created_at', ascending: false),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.teal,
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text('কোনো বেতনের ইতিহাস পাওয়া যায়নি।'),
                          );
                        }
                        final histories = snapshot.data!;
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: histories.length,
                          itemBuilder: (context, index) {
                            final history = histories[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color.fromARGB(
                                  255,
                                  91,
                                  104,
                                  103,
                                ),
                                child: Icon(
                                  Icons.receipt_long,
                                  color: Colors.teal,
                                ),
                              ),
                              title: Text('মাস: ${history['month']}'),
                              subtitle: Text(
                                'তারিখ: ${history['payment_date']}',
                              ),
                              trailing: Text(
                                '৳ ${history['amount']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 15,
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
        );
      },
    );
  }

  // শিক্ষকের বিস্তারিত প্রোফাইল পপআপ দেখার ফাংশন
  void _showTeacherProfile(Map<String, dynamic> teacher) {
    showDialog(
      context: context,
      builder: (context) {
        final photoUrl = teacher['photo_url'];
        String roleText = 'শিক্ষক (Teacher)';
        if (teacher['role'] == 'super_admin') {
          roleText = 'প্রধান শিক্ষক (Super Admin)';
        } else if (teacher['role'] == 'staff') {
          roleText = 'কর্মচারী (Staff)';
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.teal.shade100,
                  backgroundImage:
                      photoUrl != null && photoUrl.toString().isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.toString().isEmpty
                      ? const Icon(Icons.person, size: 50, color: Colors.teal)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  teacher['full_name'] ?? 'নামহীন ব্যক্তি',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'পদবি: $roleText',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const Divider(height: 24),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.phone, color: Colors.teal),
                  title: const Text('মোবাইল নম্বর'),
                  subtitle: Text(teacher['phone'] ?? 'সংযুক্ত নেই'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.email, color: Colors.teal),
                  title: const Text('ইমেইল'),
                  subtitle: Text(teacher['email'] ?? 'সংযুক্ত নেই'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments, color: Colors.teal),
                  title: const Text('মূল মাসিক বেতন'),
                  subtitle: Text('৳ ${teacher['salary'] ?? 0}'),
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
  }

  @override
  Widget build(BuildContext context) {
    // সার্চ কোয়েরি অনুযায়ী ফিল্টার করা
    final filteredList = _allTeachersAndStaff.where((item) {
      final name = (item['full_name'] ?? '').toLowerCase();
      return name.contains(searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        // অ্যাপবারে সার্চবার টগল করার ব্যবস্থা
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'শিক্ষক বা স্টাফের নাম দিয়ে খুঁজুন...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value.toLowerCase();
                  });
                },
              )
            : Text(
                widget.isReadOnly
                    ? 'শিক্ষক ও স্টাফদের বেতন তথ্য'
                    : 'শিক্ষক ও স্টাফ বেতন ব্যবস্থাপনা',
              ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              // ইউজারকে বোঝানোর জন্য সেরা উপায়ে লোডিং দেখানো হচ্ছে
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 12),
                  Text(
                    'ডেটা লোড হচ্ছে, দয়া করে অপেক্ষা করুন...',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : filteredList.isEmpty
          ? const Center(child: Text('কোনো শিক্ষক বা স্টাফ পাওয়া যায়নি!'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final teacher = filteredList[index];
                final teacherName = teacher['full_name'] ?? 'নাম নেই';
                final double monthlySalary =
                    double.tryParse(teacher['salary']?.toString() ?? '0') ??
                    0.0;
                final photoUrl = teacher['photo_url'];
                final role = teacher['role'];

                String roleBadgeText = 'শিক্ষক';
                Color roleBadgeColor = Colors.teal;
                if (role == 'super_admin') {
                  roleBadgeText = 'প্রধান শিক্ষক';
                  roleBadgeColor = Colors.orange;
                } else if (role == 'staff') {
                  roleBadgeText = 'স্টাফ';
                  roleBadgeColor = Colors.blue;
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 1.5,
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
                            GestureDetector(
                              onTap: () => _showTeacherProfile(teacher),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.teal.shade100,
                                backgroundImage:
                                    photoUrl != null &&
                                        photoUrl.toString().isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child:
                                    photoUrl == null ||
                                        photoUrl.toString().isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.teal,
                                        size: 24,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showTeacherProfile(teacher),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            teacherName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Colors.teal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: roleBadgeColor.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: roleBadgeColor,
                                            ),
                                          ),
                                          child: Text(
                                            roleBadgeText,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: roleBadgeColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'মূল বেতন: ৳ $monthlySalary',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    FutureBuilder<Map<String, dynamic>>(
                                      future: _calculateTeacherDue(
                                        teacher['id'],
                                        monthlySalary,
                                      ),
                                      builder: (context, dueSnapshot) {
                                        if (!dueSnapshot.hasData) {
                                          return const Text(
                                            'বকেয়া হিসাব হচ্ছে...',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          );
                                        }
                                        final dueData = dueSnapshot.data!;
                                        final double dueAmount =
                                            dueData['due'] ?? 0.0;

                                        return Text(
                                          'বকেয়া: ৳ ${dueAmount.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: dueAmount > 0
                                                ? Colors.redAccent
                                                : Colors.green,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!widget.isReadOnly)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 0,
                                    ),
                                    minimumSize: const Size(60, 32),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      _showAddSalaryDialog(teacher),
                                  child: const Text(
                                    'বেতন দিন',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Divider(height: 16),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: supabase
                              .from('teacher_salary_history')
                              .select()
                              .eq('teacher_id', teacher['id'])
                              .eq('academy_id', widget.academyId)
                              .order('created_at', ascending: false)
                              .limit(1),
                          builder: (context, historySnapshot) {
                            if (!historySnapshot.hasData ||
                                historySnapshot.data!.isEmpty) {
                              return const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'সর্বশেষ পেমেন্ট: এখনো দেওয়া হয়নি',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              );
                            }
                            final latestHistory = historySnapshot.data!.first;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'সর্বশেষ: ${latestHistory['month']} (${latestHistory['payment_date']}) - ৳ ${latestHistory['amount']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(50, 25),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () =>
                                      _showAllSalaryHistory(teacher),
                                  child: const Text(
                                    'সব ইতিহাস →',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold,
                                    ),
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
            ),
    );
  }
}
