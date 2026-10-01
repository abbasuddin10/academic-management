import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClassWiseStudentsView extends StatefulWidget {
  final String academyId;
  const ClassWiseStudentsView({super.key, required this.academyId});

  @override
  State<ClassWiseStudentsView> createState() => _ClassWiseStudentsViewState();
}

class _ClassWiseStudentsViewState extends State<ClassWiseStudentsView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];

  final TextEditingController _searchController = TextEditingController();
  String _selectedClassFilter = 'সকল শ্রেণি';
  List<String> _classList = ['সকল শ্রেণি'];

  @override
  void initState() {
    super.initState();
    _fetchStudents();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // সুপাবেস থেকে নির্দিষ্ট একাডেমির স্টুডেন্ট ডাটা ফেচ করা
  Future<void> _fetchStudents() async {
    try {
      setState(() => _isLoading = true);
      final response = await supabase
          .from('students')
          .select()
          .eq('academy_id', widget.academyId)
          .order('class', ascending: true);

      List<Map<String, dynamic>> students = List<Map<String, dynamic>>.from(
        response,
      );

      // ডাইনামিক ক্লাস লিস্ট তৈরি
      Set<String> uniqueClasses = {'সকল শ্রেণি'};
      for (var st in students) {
        if (st['class'] != null && st['class'].toString().trim().isNotEmpty) {
          uniqueClasses.add(st['class'].toString().trim());
        }
      }

      setState(() {
        _allStudents = students;
        _classList = uniqueClasses.toList();
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

  // সার্চ এবং ক্লাস ফিল্টার লজিক
  void _filterStudents() {
    String query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredStudents = _allStudents.where((student) {
        final name = (student['name'] ?? '').toString().toLowerCase();
        final roll = (student['roll'] ?? '').toString().toLowerCase();
        final fatherName = (student['father_name'] ?? '')
            .toString()
            .toLowerCase();
        final studentClass = student['class'] ?? '';

        bool matchesSearch =
            name.contains(query) ||
            roll.contains(query) ||
            fatherName.contains(query);
        bool matchesClass =
            (_selectedClassFilter == 'সকল শ্রেণি' ||
            studentClass == _selectedClassFilter);

        return matchesSearch && matchesClass;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    int totalCount = _filteredStudents.length;
    double totalFee = _filteredStudents.fold(0.0, (sum, item) {
      return sum +
          (double.tryParse(item['monthly_fee']?.toString() ?? '0') ?? 0.0);
    });

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('ক্লাস ভিত্তিক শিক্ষার্থী ব্যবস্থাপনা'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'রিফ্রেশ',
            onPressed: _fetchStudents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
              children: [
                // ১. স্ট্যাটাস ওভারভিউ কার্ড (মোট শিক্ষার্থী ও মোট সম্ভাব্য ফি)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.teal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'নির্বাচিত ফিল্ডে মোট',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalCount জন শিক্ষার্থী',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'মোট মাসিক প্রাপ্য বেতন',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '৳ ${totalFee.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ২. হরিজন্টাল ক্লাস ফিল্টার চিপস
                Container(
                  height: 55,
                  color: Colors.white,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
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

                // ৩. সার্চ বক্স
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'নাম, রোল বা পিতার নাম দিয়ে খুঁজুন...',
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
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),

                // ৪. স্টুডেন্ট লিস্ট ভিউ
                Expanded(
                  child: _filteredStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 60,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'কোনো শিক্ষার্থী পাওয়া যায়নি!',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            final name = student['name'] ?? 'নামহীন';
                            final className = student['class'] ?? '';
                            final roll = student['roll'] ?? '';
                            final fatherName =
                                student['father_name'] ?? 'প্রযোজ্য নয়';
                            final fee = student['monthly_fee'] ?? 0;
                            final imageUrl = student['image_url'];

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.teal.shade100,
                                  backgroundImage:
                                      imageUrl != null &&
                                          imageUrl.toString().isNotEmpty
                                      ? NetworkImage(imageUrl)
                                      : null,
                                  child:
                                      imageUrl == null ||
                                          imageUrl.toString().isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.teal,
                                          size: 30,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      'শ্রেণি: $className | রোল: $roll',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'পিতার নাম: $fatherName',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'মাসিক বেতন: ৳ $fee',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                      ),
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
