import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentFeeCollectionPage extends StatefulWidget {
  final String academyId;

  const StudentFeeCollectionPage({super.key, required this.academyId});

  @override
  State<StudentFeeCollectionPage> createState() =>
      _StudentFeeCollectionPageState();
}

class _StudentFeeCollectionPageState extends State<StudentFeeCollectionPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _selectedClassFilter = 'সকল শ্রেণি';
  List<String> _classList = ['সকল শ্রেণি'];

  @override
  void initState() {
    super.initState();
    _fetchAcademyStudents();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // সুপাবেস থেকে নির্দিষ্ট একাডেমির স্টুডেন্ট ফেচ করা
  Future<void> _fetchAcademyStudents() async {
    try {
      setState(() => _isLoading = true);

      final response = await supabase
          .from('students')
          .select()
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> fetchedStudents =
          List<Map<String, dynamic>>.from(response);

      // ডাইনামিক ক্লাস লিস্ট তৈরি
      Set<String> uniqueClasses = {'সকল শ্রেণি'};
      for (var student in fetchedStudents) {
        if (student['class'] != null &&
            student['class'].toString().trim().isNotEmpty) {
          uniqueClasses.add(student['class'].toString().trim());
        }
      }

      setState(() {
        _allStudents = fetchedStudents;
        _classList = uniqueClasses.toList();

        if (!_classList.contains(_selectedClassFilter)) {
          _selectedClassFilter = 'সকল শ্রেণি';
        }

        _filterStudents();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        "ত্রুটি",
        "ডাটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // সার্চ এবং শ্রেণি ফিল্টার লজিক
  void _filterStudents() {
    String query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredStudents = _allStudents.where((student) {
        final name = (student['name'] ?? '').toString().toLowerCase();
        final roll = (student['roll'] ?? '').toString().toLowerCase();
        final studentClass = student['class'] ?? '';

        bool matchesSearch = name.contains(query) || roll.contains(query);
        bool matchesClass =
            (_selectedClassFilter == 'সকল শ্রেণি' ||
            studentClass == _selectedClassFilter);

        return matchesSearch && matchesClass;
      }).toList();
    });
  }

  // ফি পেমেন্ট ডায়ালগ বক্স
  void _showCollectFeeDialog(Map<String, dynamic> student) {
    final TextEditingController amountController = TextEditingController(
      text: student['monthly_fee']?.toString() ?? '',
    );
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

    Get.defaultDialog(
      title: "${student['name'] ?? 'শিক্ষার্থী'} - এর ফি গ্রহণ",
      titleStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      content: SizedBox(
        width: 300,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: selectedMonth,
                        decoration: const InputDecoration(labelText: 'মাস'),
                        items: months
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: const InputDecoration(labelText: 'বছর'),
                        items:
                            List.generate(5, (i) => DateTime.now().year - 2 + i)
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y'),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedYear = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'টাকার পরিমাণ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      textConfirm: "জমা দিন",
      textCancel: "বাতিল",
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
        if (amount <= 0) {
          Get.snackbar(
            "সতর্কতা",
            "সঠিক পরিমাণ টাকা লিখুন",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        try {
          await supabase.from('student_fee_history').insert({
            'academy_id': widget.academyId,
            'student_id': student['id'],
            'month': '$selectedMonth $selectedYear',
            'amount': amount,
            'payment_date': DateTime.now().toIso8601String().split('T')[0],
          });

          Get.back();
          Get.snackbar(
            "সফল",
            "ফি সফলভাবে জমা হয়েছে!",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
          _fetchAcademyStudents();
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "ত্রুটি: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // নতুন "অন্যান্য" কালেকশন ডায়ালগ বক্স (স্টুডেন্টের সকল তথ্যসহ সেভ হবে)
  void _showOtherCollectionDialog(Map<String, dynamic> student) {
    String? selectedCategory = 'ভর্তি ফি';
    final TextEditingController customCategoryController =
        TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController noteController = TextEditingController();

    final List<String> defaultCategories = [
      'ভর্তি ফি',
      'পরীক্ষার ফি',
      'সেশন ফি',
      'ম্যাগাজিন ফি',
      'অন্যান্য (নিজে লিখুন)',
    ];

    Get.defaultDialog(
      title: "${student['name'] ?? 'শিক্ষার্থী'} - এর অন্যান্য ফি/টাকা",
      titleStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.indigo,
      ),
      content: SizedBox(
        width: 320,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            bool isFormValid =
                amountController.text.trim().isNotEmpty &&
                (selectedCategory != 'অন্যান্য (নিজে লিখুন)' ||
                    customCategoryController.text.trim().isNotEmpty);

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'খাতের ধরন সিলেক্ট করুন',
                      border: OutlineInputBorder(),
                    ),
                    items: defaultCategories
                        .map(
                          (cat) =>
                              DropdownMenuItem(value: cat, child: Text(cat)),
                        )
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedCategory = val;
                      });
                    },
                  ),
                  if (selectedCategory == 'অন্যান্য (নিজে লিখুন)') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customCategoryController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'খাতের নাম লিখুন',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'টাকার পরিমাণ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'নোট (ঐচ্ছিক বিবরণ)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFormValid
                            ? Colors.indigo
                            : Colors.indigo.shade200,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: !isFormValid
                          ? null
                          : () async {
                              final amount =
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0.0;
                              String finalCategory =
                                  selectedCategory == 'অন্যান্য (নিজে লিখুন)'
                                  ? customCategoryController.text.trim()
                                  : selectedCategory!;

                              if (amount <= 0) return;

                              try {
                                // কার্ডে থাকা নাম, শ্রেণি, রোল, ফোন এবং পিতার নাম সহ সুপাবেসে সেভ করা হচ্ছে
                                await supabase
                                    .from('student_other_collections')
                                    .insert({
                                      'academy_id': widget.academyId,
                                      'student_id': student['id'],
                                      'student_name': student['name'] ?? '',
                                      'student_class': student['class'] ?? '',
                                      'student_roll': student['roll'] ?? '',
                                      'phone': student['phone'] ?? '',
                                      'father_name':
                                          student['father_name'] ??
                                          student['father'] ??
                                          '',
                                      'category': finalCategory,
                                      'amount': amount,
                                      'note':
                                          noteController.text.trim().isNotEmpty
                                          ? noteController.text.trim()
                                          : null,
                                      'payment_date': DateTime.now()
                                          .toIso8601String()
                                          .split('T')[0],
                                    });

                                Get.back();
                                Get.snackbar(
                                  "সফল",
                                  "অন্যান্য খাতের টাকা সফলভাবে জমা হয়েছে!",
                                  backgroundColor: Colors.green,
                                  colorText: Colors.white,
                                );
                                _fetchAcademyStudents();
                              } catch (e) {
                                Get.snackbar(
                                  "ত্রুটি",
                                  "ত্রুটি: $e",
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                              }
                            },
                      child: const Text('সাবমিট করুন'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      textCancel: "বাতিল",
      cancelTextColor: Colors.grey,
      onConfirm: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('বেতন ও ফি সংগ্রহ'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'রিফ্রেশ করুন',
            onPressed: () => _fetchAcademyStudents(),
          ),
        ],
      ),
      body: Column(
        children: [
          // হরিজন্টাল ক্লাস বাটন লিস্ট (ডাইনামিক ফিল্টার)
          Container(
            height: 55,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _classList.length,
              itemBuilder: (context, index) {
                final className = _classList[index];
                final isSelected = _selectedClassFilter == className;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(className),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    backgroundColor: Colors.grey.shade200,
                    onSelected: (bool selected) {
                      setState(() {
                        _selectedClassFilter = className;
                      });
                      _filterStudents();
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, thickness: 1),

          // সার্চ বক্স
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'শিক্ষার্থীর নাম বা রোল দিয়ে খুঁজুন...',
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterStudents();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // স্টুডেন্ট লিস্ট এবং ফি কালেকশন কার্ড
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.teal),
                  )
                : _filteredStudents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 65,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'কোনো শিক্ষার্থীর তথ্য পাওয়া যায়নি!',
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _filteredStudents.length,
                    itemBuilder: (context, index) {
                      final student = _filteredStudents[index];
                      final studentName = student['name'] ?? 'নামহীন';
                      final studentClass = student['class'] ?? 'শ্রেণি নেই';
                      final studentRoll = student['roll'] ?? 'নেই';
                      final monthlyFee = student['monthly_fee'] ?? 0;
                      final phone = student['phone'] ?? 'প্রযোজ্য নয়';
                      final fatherName =
                          student['father_name'] ??
                          student['father'] ??
                          'অভিভাবকের নাম নেই';

                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // প্রোফাইল ছবি
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.teal.shade100,
                                backgroundImage:
                                    student['image_url'] != null &&
                                        student['image_url']
                                            .toString()
                                            .isNotEmpty
                                    ? NetworkImage(student['image_url'])
                                    : null,
                                child:
                                    student['image_url'] == null ||
                                        student['image_url'].toString().isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.teal,
                                        size: 26,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),

                              // শিক্ষার্থীর বিস্তারিত তথ্য
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      studentName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$studentClass | রোল: $studentRoll',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'মাসিক ফি: ৳ $monthlyFee\nমোবাইল: $phone\nপিতা: $fatherName',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 11,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // ওভারফ্লো রোধ করতে বাটন দুটিকে Column এ ফিক্সড সাইজে রাখা হয়েছে
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 72,
                                    height: 28,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),
                                      onPressed: () =>
                                          _showCollectFeeDialog(student),
                                      icon: const Icon(Icons.payment, size: 10),
                                      label: const Text(
                                        'ফি নিন',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 6,
                                  ), // এখানে দুটি বাটনের মাঝের দূরত্ব ৬ রাখা হয়েছে
                                  SizedBox(
                                    width: 72,
                                    height: 28,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),
                                      onPressed: () =>
                                          _showOtherCollectionDialog(student),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 10,
                                      ),
                                      label: const Text(
                                        'অন্যান্য',
                                        style: TextStyle(fontSize: 10),
                                      ),
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
