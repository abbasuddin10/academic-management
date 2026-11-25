import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/repositories/student_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/widgets/async_state_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'add_student_view.dart';

class StudentsView extends StatefulWidget {
  final String userRole; // ইউজার রোল রিসিভ করার জন্য ভেরিয়েবল
  const StudentsView({super.key, this.userRole = 'super_admin'});

  @override
  State<StudentsView> createState() => _StudentsViewState();
}

class _StudentsViewState extends State<StudentsView> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();
  String _selectedClassFilter = 'সকল শ্রেণি';

  // ডাইনামিক ক্লাসের তালিকা
  List<String> _classList = ['সকল শ্রেণি'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAcademyStudents();
    });
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // সুপাবেস ডাটাবেস থেকে স্টুডেন্ট ফেচ করা এবং নির্দিষ্ট প্রতিষ্ঠানের ডাটা ফিল্টার করা
  Future<void> _fetchAcademyStudents() async {
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final academyId = await AcademyRepository().currentUserAcademyId();
      if (academyId == null || academyId.isEmpty) {
        throw "ইউজার লগইন করা নেই অথবা ইমেল পাওয়া যায়নি!";
      }

      final fetchedStudents = (await StudentRepository().fetchByAcademy(
        academyId,
      ))
          .map((student) => student.toMap())
          .toList();

      // ৩. ডাটা থেকে ইউনিক ক্লাসগুলো বের করে ডাইনামিক ক্লাস লিস্ট তৈরি করা
      Set<String> uniqueClasses = {'সকল শ্রেণি'};
      for (var student in fetchedStudents) {
        if (student['class'] != null &&
            student['class'].toString().trim().isNotEmpty) {
          uniqueClasses.add(student['class'].toString().trim());
        }
      }

      if (mounted) {
        setState(() {
          _allStudents = fetchedStudents;
          _classList = uniqueClasses.toList();

          if (!_classList.contains(_selectedClassFilter)) {
            _selectedClassFilter = 'সকল শ্রেণি';
          }

          _filterStudents();
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
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

  // সুপাবেস থেকে পার্মানেন্টলি ডিলিট করার ফাংশন
  Future<void> _deleteStudentFromDatabase(
    String studentId,
    String studentName,
    String academyId,
  ) async {
    try {
      await StudentRepository().delete(studentId, academyId);

      Get.snackbar(
        "সফল",
        "'$studentName'-এর তথ্য সফলভাবে মুছে ফেলা হয়েছে",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      _fetchAcademyStudents();
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ডিলিট করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      _fetchAcademyStudents();
    }
  }

  // এডিট ডায়লগ এবং সুপাবেস আপডেট
  void _showEditStudentDialog(Map<String, dynamic> student) {
    final nameController = TextEditingController(text: student['name']);
    final fatherController = TextEditingController(
      text: student['father_name'],
    );
    final rollController = TextEditingController(
      text: student['roll'].toString(),
    );
    final phoneController = TextEditingController(text: student['phone']);
    final feeController = TextEditingController(
      text: student['monthly_fee'].toString(),
    );
    final addressController = TextEditingController(text: student['address']);

    Get.defaultDialog(
      title: "শিক্ষার্থীর তথ্য আপডেট",
      titleStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'শিক্ষার্থীর নাম'),
              ),
              TextField(
                controller: fatherController,
                decoration: const InputDecoration(labelText: 'পিতার নাম'),
              ),
              TextField(
                controller: rollController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'রোল নম্বর'),
              ),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'মোবাইল নম্বর'),
              ),
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'মাসিক বেতন'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'ঠিকানা'),
              ),
            ],
          ),
        ),
      ),
      textConfirm: "সংরক্ষণ করুন",
      textCancel: "বাতিল",
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        try {
          final updatedData = {
            'name': nameController.text.trim(),
            'father_name': fatherController.text.trim(),
            'roll': rollController.text.trim(),
            'phone': phoneController.text.trim(),
            'monthly_fee': double.tryParse(feeController.text.trim()) ?? 0.0,
            'address': addressController.text.trim(),
          };

          await supabase
              .from('students')
              .update(updatedData)
              .eq('id', student['id']);

          Get.back();
          Get.snackbar(
            "সফল",
            "তথ্য সফলভাবে আপডেট করা হয়েছে!",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );

          _fetchAcademyStudents();
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "আপডেট করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // ব্যানার অ্যাড তৈরি করার হেল্পার উইজেট (প্রতি ২টা কার্ড পর পর দেখানোর জন্য)
  Widget _buildBannerAdItem() {
    final BannerAd bannerAd = AdService.createBannerAd()..load();
    return Container(
      alignment: Alignment.center,
      margin: EdgeInsets.symmetric(vertical: 6),
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: const Text('ছাত্র-ছাত্রী তালিকা'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'শ্রেণি ফিল্টার',
            onSelected: (String value) {
              setState(() {
                _selectedClassFilter = value;
              });
              _filterStudents();
            },
            itemBuilder: (BuildContext context) {
              return _classList.map((String className) {
                return PopupMenuItem<String>(
                  value: className,
                  child: Text(
                    className,
                    style: TextStyle(
                      fontWeight: _selectedClassFilter == className
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _selectedClassFilter == className
                          ? Colors.teal
                          : AppTheme.inkOf(context),
                    ),
                  ),
                );
              }).toList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'রিফ্রেশ করুন',
            onPressed: () => _fetchAcademyStudents(),
          ),
        ],
      ),
      body: Column(
        children: [
          // হরিজন্টাল ক্লাস বাটন লিস্ট
          Container(
            height: 55,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _classList.length,
              itemBuilder: (context, index) {
                final className = _classList[index];
                final isSelected = _selectedClassFilter == className;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(className),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.inkOf(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    backgroundColor: AppTheme.borderOf(context),
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
                prefixIcon: Icon(Icons.search, color: Colors.teal),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterStudents();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.borderOf(context)),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // স্টুডেন্ট লিস্ট
          Expanded(
            child: _isLoading
                ? const AppLoadingState(message: 'শিক্ষার্থী লোড হচ্ছে...')
                : _errorMessage != null
                ? AppErrorState(
                    message: 'ডাটা লোড করতে সমস্যা হয়েছে।',
                    onRetry: _fetchAcademyStudents,
                  )
                : _filteredStudents.isEmpty
                ? const AppEmptyState(
                    icon: Icons.search_off,
                    message: 'কোনো শিক্ষার্থীর তথ্য পাওয়া যায়নি!',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount:
                        _filteredStudents.length +
                        (_filteredStudents.isNotEmpty
                            ? (_filteredStudents.length ~/ 2)
                            : 0),
                    itemBuilder: (context, index) {
                      // প্রতি ২ টা কার্ড পর পর ব্যানার অ্যাড দেখানোর হিসাব
                      int realIndex = index;
                      for (int i = 0; i <= index; i++) {
                        if (i > 0 && (i + 1) % 3 == 0) {
                          if (index == i) {
                            return _buildBannerAdItem();
                          }
                          realIndex--;
                        }
                      }

                      if (realIndex >= _filteredStudents.length) {
                        return const SizedBox.shrink();
                      }

                      final student = _filteredStudents[realIndex];
                      final studentId = student['id'].toString();
                      final studentName = student['name'] ?? 'নামহীন';

                      final studentCardWidget = Card(
                        elevation: 2,
                        margin: EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: AppTheme.tileOf(context, Colors.teal),
                            backgroundImage:
                                student['image_url'] != null &&
                                    student['image_url'].toString().isNotEmpty
                                ? NetworkImage(student['image_url'])
                                : null,
                            child:
                                student['image_url'] == null ||
                                    student['image_url'].toString().isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.teal,
                                    size: 28,
                                  )
                                : null,
                          ),
                          title: Text(
                            studentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 4),
                              Text(
                                'শ্রেণি: ${student['class'] ?? ''} | রোল: ${student['roll'] ?? ''}',
                              ),
                              Text(
                                'মোবাইল: ${student['phone'] ?? 'প্রযোজ্য নয়'}',
                                style: TextStyle(
                                  color: AppTheme.mutedOf(context),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'পাসওয়ার্ড: সংরক্ষিত (দেখা যাবে না)',
                                style: TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      // ইউজার যদি 'teacher' হয়, তবে শুধু কার্ড দেখাবে (কোনো ডিসমিসিবল বা এডিট-ডিলিট কাজ করবে না)
                      if (widget.userRole == 'teacher') {
                        return studentCardWidget;
                      }

                      // সুপার অ্যাডমিনের জন্য Dismissible (এডিট ও ডিলিট সুবিধা সহ) কাজ করবে
                      return Dismissible(
                        key: Key(studentId),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.delete, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'ডিলিট',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'এডিট',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.edit, color: Colors.white),
                            ],
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.endToStart) {
                            _showEditStudentDialog(student);
                            return false;
                          } else {
                            bool confirm = false;
                            await Get.defaultDialog(
                              title: "শিক্ষার্থী ডিলিট",
                              middleText:
                                  "আপনি কি নিশ্চিতভাবে '$studentName'-এর তথ্য মুছে ফেলতে চান?",
                              textConfirm: "হ্যাঁ, ডিলিট",
                              textCancel: "না",
                              confirmTextColor: Colors.white,
                              buttonColor: Colors.red,
                              onConfirm: () {
                                confirm = true;
                                Get.back();
                              },
                              onCancel: () {
                                confirm = false;
                              },
                            );
                            if (confirm) {
                              await _deleteStudentFromDatabase(
                                studentId,
                                studentName,
                                student['academy_id']?.toString() ?? '',
                              );
                              return true;
                            }
                            return false;
                          }
                        },
                        child: studentCardWidget,
                      );
                    },
                  ),
          ),
        ],
      ),
      // শিক্ষক হলে নতুন শিক্ষার্থী যোগ করার ফ্লোটিং বাটন থাকবে না, সুপার এডমিন হলে থাকবে
      floatingActionButton: widget.userRole == 'teacher'
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              onPressed: () async {
                await Get.to(() => const AddStudentView());
                _fetchAcademyStudents();
              },
              icon: const Icon(Icons.person_add),
              label: const Text('ছাত্র যোগ করুন'),
            ),
    );
  }
}
