import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class TeachersView extends StatefulWidget {
  final String adminUserName;

  const TeachersView({super.key, required this.adminUserName});

  @override
  State<TeachersView> createState() => _TeachersViewState();
}

class _TeachersViewState extends State<TeachersView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> teachersList = [];
  List<Map<String, dynamic>> filteredTeachersList = [];
  bool isLoading = true;
  String? academyId;
  String academyName = 'লোড হচ্ছে...';

  final TextEditingController _searchController = TextEditingController();

  // সার্চ মোড টগল করার জন্য ভেরিয়েবল
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchTeachersAndAcademy();
    _searchController.addListener(_filterTeachers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // শিক্ষক ও অ্যাকাডেমির ডেটা ফেচ করা (ইমেইল দিয়ে আপডেট করা হলো)
  Future<void> _fetchTeachersAndAcademy() async {
    try {
      setState(() => isLoading = true);

      final currentUserEmail = supabase.auth.currentUser?.email;
      if (currentUserEmail == null) {
        throw 'লগইন করা ইউজারের ইমেইল পাওয়া যায়নি!';
      }

      final adminData = await supabase
          .from('users')
          .select('*')
          .eq('email', currentUserEmail)
          .single();

      academyId = adminData['academy_id'];

      if (academyId != null) {
        final academyResponse = await supabase
            .from('academies')
            .select()
            .eq('id', academyId!)
            .maybeSingle();

        if (academyResponse != null) {
          academyName =
              academyResponse['academy_name'] ?? 'নামবিহীন প্রতিষ্ঠান';
        } else {
          academyName = 'প্রতিষ্ঠান পাওয়া যায়নি';
        }
      }

      final response = await supabase
          .from('users')
          .select('*')
          .eq('academy_id', academyId!);

      setState(() {
        teachersList = List<Map<String, dynamic>>.from(response);
        _filterTeachers(); // ফিল্টার লিস্ট আপডেট করা
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar(
        "ত্রুটি",
        "ডেটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // সার্চ ফিল্টার লজিক
  void _filterTeachers() {
    String query = _searchController.text.trim().toLowerCase();
    setState(() {
      filteredTeachersList = teachersList.where((teacher) {
        String name = (teacher['full_name'] ?? '').toString().toLowerCase();
        String phone = (teacher['phone'] ?? '').toString().toLowerCase();
        return name.contains(query) || phone.contains(query);
      }).toList();
    });
  }

  // শিক্ষকের বেতন আপডেট করার পপআপ ডায়ালগ
  void _showUpdateSalaryDialog(
    String teacherId,
    String teacherName,
    String currentSalary,
  ) {
    final TextEditingController salaryController = TextEditingController(
      text: currentSalary,
    );

    Get.defaultDialog(
      title: 'বেতন আপডেট করুন',
      titleStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'শিক্ষক/কর্মী: $teacherName',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: salaryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'নতুন বেতন (টাকা)',
                prefixIcon: Icon(Icons.money, color: Colors.teal),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      textConfirm: 'সংরক্ষণ',
      textCancel: 'বাতিল',
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        String salaryText = salaryController.text.trim();
        if (salaryText.isEmpty) {
          Get.snackbar(
            "সতর্কতা",
            "বেতনের পরিমাণ খালি রাখা যাবে না!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        // Numeric কলামের জন্য সংখ্যায় রূপান্তর করা
        num? parsedSalary = num.tryParse(salaryText);
        if (parsedSalary == null) {
          Get.snackbar(
            "ত্রুটি",
            "দয়া করে সঠিক সংখ্যা লিখুন!",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        try {
          Get.back(); // ডায়ালগ বন্ধ করা

          // সুপাবেসে সংখ্যা হিসেবে বেতন আপডেট করা
          await supabase
              .from('users')
              .update({'salary': parsedSalary})
              .eq('id', teacherId);

          Get.snackbar(
            "সফল",
            "'$teacherName'-এর বেতন সফলভাবে আপডেট করা হয়েছে।",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );

          _fetchTeachersAndAcademy(); // ডাটা রিফ্রেশ করা
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "বেতন আপডেট করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // শিক্ষক বা সুপার অ্যাডমিন ডিলিট করার ফাংশন (সুরক্ষিত)
  void _deleteTeacher(String teacherId, String teacherName, String role) {
    if (role == 'super_admin') {
      Get.snackbar(
        "সতর্কতা",
        "প্রধান শিক্ষক (Super Admin)-কে ডিলিট করা নিষেধ বা সম্ভব নয়!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    Get.defaultDialog(
      title: 'মুছে ফেলুন',
      middleText:
          'আপনি কি নিশ্চিতভাবে "$teacherName" কে ডাটাবেস এবং অ্যাপ থেকে চিরতরে মুছে ফেলতে চান?',
      textConfirm: 'হ্যাঁ, ডিলিট',
      textCancel: 'বাতিল',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () async {
        try {
          Get.back();

          await supabase.from('users').delete().eq('id', teacherId);

          Get.snackbar(
            "সফল",
            "সফলভাবে ডাটাবেস ও অ্যাপ থেকে মুছে ফেলা হয়েছে।",
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );

          _fetchTeachersAndAcademy();
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "ডিলিট করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // শিক্ষক অথবা কর্মচারী যুক্ত করার ডায়ালগ (userRole: 'teacher' অথবা 'staff')
  void _showAddUserDialog(String userRole) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController salaryController = TextEditingController();

    File? selectedImage;
    final ImagePicker picker = ImagePicker();

    String titleText = userRole == 'teacher'
        ? 'নতুন শিক্ষক যুক্ত করুন'
        : 'নতুন কর্মচারী যুক্ত করুন';

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> pickImage() async {
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (image != null) {
                setStateDialog(() {
                  selectedImage = File(image.path);
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: pickImage,
                      child: CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.teal.shade100,
                        backgroundImage: selectedImage != null
                            ? FileImage(selectedImage!)
                            : null,
                        child: selectedImage == null
                            ? const Icon(
                                Icons.add_a_photo,
                                size: 28,
                                color: Colors.teal,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ছবি পরিবর্তন করতে ট্যাপ করুন',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: userRole == 'teacher'
                            ? 'শিক্ষকের নাম'
                            : 'কর্মচারীর নাম',
                        prefixIcon: const Icon(Icons.person),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'ইমেইল',
                        prefixIcon: Icon(Icons.email),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'ফোন নম্বর',
                        prefixIcon: Icon(Icons.phone),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: salaryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'বেতন (টাকা)',
                        prefixIcon: Icon(Icons.money),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'পাসওয়ার্ড (প্লেইন টেক্সট)',
                        prefixIcon: Icon(Icons.lock),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (nameController.text.isEmpty ||
                            emailController.text.isEmpty ||
                            passwordController.text.isEmpty) {
                          Get.snackbar(
                            "সতর্কতা",
                            "নাম, ইমেইল এবং পাসওয়ার্ড আবশ্যক!",
                            backgroundColor: Colors.orange,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        try {
                          String? uploadedImageUrl;

                          if (selectedImage != null) {
                            final fileName =
                                '${DateTime.now().millisecondsSinceEpoch}.jpg';
                            final path = 'teacher_photos/$fileName';

                            await supabase.storage
                                .from('teacher_photos')
                                .upload(path, selectedImage!);
                            uploadedImageUrl = supabase.storage
                                .from('teacher_photos')
                                .getPublicUrl(path);
                          }

                          await supabase.from('users').insert({
                            'academy_id': academyId,
                            'email': emailController.text.trim(),
                            'password': passwordController.text.trim(),
                            'full_name': nameController.text.trim(),
                            'phone': phoneController.text.trim(),
                            'salary': salaryController.text.trim(),
                            'photo_url': uploadedImageUrl,
                            'role': userRole, // 'teacher' অথবা 'staff'
                          });

                          Get.back();
                          Get.snackbar(
                            "সফল",
                            "সফলভাবে যুক্ত হয়েছেন!",
                            backgroundColor: Colors.green,
                            colorText: Colors.white,
                          );
                          _fetchTeachersAndAcademy();
                        } catch (e) {
                          Get.snackbar(
                            "ত্রুটি",
                            e.toString(),
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                        }
                      },
                      child: const Text(
                        'সংরক্ষণ করুন',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'নাম বা ফোন নম্বর দিয়ে খুঁজুন...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : const Text('শিক্ষক ও কর্মী তালিকা'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _isSearching = false;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
              children: [
                Expanded(
                  child: filteredTeachersList.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো শিক্ষক বা কর্মী পাওয়া যায়নি!',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: filteredTeachersList.length,
                          itemBuilder: (context, index) {
                            final teacher = filteredTeachersList[index];
                            bool isSuper = teacher['role'] == 'super_admin';
                            bool isStaff = teacher['role'] == 'staff';

                            String teacherId = teacher['id']?.toString() ?? '';
                            String teacherName =
                                teacher['full_name'] ?? 'নাম নেই';
                            String role = teacher['role'] ?? 'teacher';
                            String rawPassword = teacher['password'] ?? 'নেই';
                            String phone = teacher['phone'] ?? 'নথিভুক্ত নয়';
                            String salary =
                                teacher['salary']?.toString() ?? '০';
                            String? photoUrl = teacher['photo_url'];

                            // রোল অনুযায়ী ডিসপ্লে নাম ও কালার নির্ধারণ
                            String roleDisplay = 'শিক্ষক (Teacher)';
                            Color roleColor = Colors.teal.shade700;
                            if (isSuper) {
                              roleDisplay = 'প্রধান শিক্ষক (Super Admin)';
                              roleColor = Colors.orange.shade800;
                            } else if (isStaff) {
                              roleDisplay = 'কর্মচারী (Staff)';
                              roleColor = Colors.blue.shade700;
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: isSuper
                                        ? Colors.orange.shade100
                                        : (isStaff
                                              ? Colors.blue.shade100
                                              : Colors.teal.shade100),
                                    backgroundImage:
                                        (photoUrl != null &&
                                            photoUrl.isNotEmpty)
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child:
                                        (photoUrl == null || photoUrl.isEmpty)
                                        ? Icon(
                                            isSuper
                                                ? Icons.admin_panel_settings
                                                : (isStaff
                                                      ? Icons.badge
                                                      : Icons.person),
                                            color: isSuper
                                                ? Colors.orange.shade800
                                                : (isStaff
                                                      ? Colors.blue.shade800
                                                      : Colors.teal),
                                            size: 22,
                                          )
                                        : null,
                                  ),
                                  title: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          teacherName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      // সুপার অ্যাডমিন না হলে ডিলিট বাটন দেখাবে
                                      isSuper
                                          ? const SizedBox.shrink()
                                          : IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: EdgeInsets.zero,
                                              onPressed: () {
                                                _deleteTeacher(
                                                  teacherId,
                                                  teacherName,
                                                  role,
                                                );
                                              },
                                            ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text(
                                        'প্রতিষ্ঠান: $academyName',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        'ইমেইল: ${teacher['email']}\nফোন: $phone',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'বেতন: ৳ $salary',
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              _showUpdateSalaryDialog(
                                                teacherId,
                                                teacherName,
                                                salary,
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.teal.shade200,
                                                ),
                                              ),
                                              child: const Text(
                                                'বেতন পরিবর্তন',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.teal,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'পাসওয়ার্ড: $rawPassword',
                                            style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            'রোল: $roleDisplay',
                                            style: TextStyle(
                                              color: roleColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
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
            ),
      // স্মার্ট এক্সটেন্ডেড ফ্লোটিং অ্যাকশন বাটন যাতে শিক্ষক ও কর্মচারী আলাদাভাবে যোগ করা যায়
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // একটি বটম শিট বা অপশন ডায়ালগ ওপেন হবে
          Get.bottomSheet(
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'কাকে যুক্ত করতে চান?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.school, color: Colors.white),
                    ),
                    title: const Text(
                      'নতুন শিক্ষক যুক্ত করুন',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Get.back();
                      _showAddUserDialog('teacher');
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.badge, color: Colors.white),
                    ),
                    title: const Text(
                      'অন্যান্য কর্মচারী যুক্ত করুন',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Get.back();
                      _showAddUserDialog('staff');
                    },
                  ),
                ],
              ),
            ),
          );
        },
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'নতুন যুক্ত করুন',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
