import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddStudentView extends StatefulWidget {
  const AddStudentView({super.key});

  @override
  State<AddStudentView> createState() => _AddStudentViewState();
}

class _AddStudentViewState extends State<AddStudentView> {
  final _formKey = GlobalKey<FormState>();

  // টেক্সট কন্ট্রোলারসমূহ
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _rollController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _feeController = TextEditingController();

  // ড্রপডাউন, ইমেজ ও লোডিং স্টেট
  String? _selectedClass;
  bool _isLoading = false;
  bool _isFormValid = false;
  File? _selectedImage;

  // সুপাবেস থেকে লোড হওয়া ক্লাসের তালিকা
  List<Map<String, dynamic>> _classList = [];
  bool _isClassLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchClassesFromSupabase();

    _nameController.addListener(_validateForm);
    _fatherNameController.addListener(_validateForm);
    _rollController.addListener(_validateForm);
    _addressController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
    _feeController.addListener(_validateForm);
  }

  // ১. সুপাবেস থেকে বর্তমান একাডেমির ক্লাসগুলো ফেচ করা
  Future<void> _fetchClassesFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final currentUserEmail = supabase.auth.currentUser?.email;

      if (currentUserEmail == null) return;

      // বর্তমান ইউজারের academy_id বের করা
      final userData = await supabase
          .from('users')
          .select('academy_id')
          .eq('email', currentUserEmail!)
          .single();

      final academyId = userData['academy_id'];

      // classes টেবিল থেকে এই একাডেমির ক্লাসগুলো class_order অনুযায়ী সাজিয়ে আনা
      final response = await supabase
          .from('classes')
          .select()
          .eq('academy_id', academyId)
          .order('class_order', ascending: true);

      setState(() {
        _classList = List<Map<String, dynamic>>.from(response);
        _isClassLoading = false;
      });
    } catch (e) {
      setState(() {
        _isClassLoading = false;
      });
      Get.snackbar(
        "ত্রুটি",
        "ক্লাসের তালিকা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  // ফর্মে সব তথ্য ঠিকঠাক আছে কিনা তা চেক করা
  void _validateForm() {
    final isValid =
        _nameController.text.trim().isNotEmpty &&
        _fatherNameController.text.trim().isNotEmpty &&
        _rollController.text.trim().isNotEmpty &&
        _addressController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _feeController.text.trim().isNotEmpty &&
        _selectedClass != null &&
        _selectedClass != '+ নতুন শ্রেণি যোগ করুন';

    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  // ২. নতুন শ্রেণি যোগ করার ডায়ালগ (স্মার্ট হ্যান্ডলিং ও ক্রমসহ)
  void _showAddClassDialog() {
    final TextEditingController newClassController = TextEditingController();
    final TextEditingController orderController = TextEditingController(
      text: '${_classList.length + 1}',
    );

    Get.defaultDialog(
      title: 'নতুন শ্রেণি যুক্ত করুন',
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newClassController,
              decoration: InputDecoration(
                labelText: 'শ্রেণির নাম (যেমন: একাদশ শ্রেণি)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: orderController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'ক্রম বা সিরিয়াল নম্বর (যেমন: 1, 2, 3...)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
      textConfirm: 'সংরক্ষণ করুন',
      textCancel: 'বাতিল',
      confirmTextColor: Colors.white,
      buttonColor: Colors.teal,
      onConfirm: () async {
        String newClassName = newClassController.text.trim();
        int? newOrder = int.tryParse(orderController.text.trim());

        if (newClassName.isEmpty || newOrder == null) {
          Get.snackbar(
            "ত্রুটি",
            "দয়া করে সঠিক নাম এবং ক্রম নম্বর দিন",
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        // নাম আগে থেকে আছে কিনা চেক করা
        bool nameExists = _classList.any(
          (c) =>
              c['class_name'].toString().toLowerCase() ==
              newClassName.toLowerCase(),
        );

        if (nameExists) {
          Get.snackbar(
            "সতর্কতা",
            "এই নামের শ্রেণি ইতিমধ্যে তালিকায় রয়েছে!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        try {
          final supabase = Supabase.instance.client;
          final currentUserEmail = supabase.auth.currentUser?.email;
          final userData = await supabase
              .from('users')
              .select('academy_id')
              .eq('email', currentUserEmail!)
              .single();
          final academyId = userData['academy_id'];

          // ক্রম আগে থেকে থাকলে বাকিগুলোর ক্রম এক ঘর বাড়িয়ে দেওয়া (Shift করা)
          bool orderExists = _classList.any(
            (c) => c['class_order'] == newOrder,
          );
          if (orderExists) {
            for (var cls in _classList) {
              if (cls['class_order'] >= newOrder) {
                await supabase
                    .from('classes')
                    .update({'class_order': cls['class_order'] + 1})
                    .eq('id', cls['id']);
              }
            }
          }

          // সুপাবেসে নতুন ক্লাস ইনসার্ট করা
          await supabase.from('classes').insert({
            'academy_id': academyId,
            'class_name': newClassName,
            'class_order': newOrder,
          });

          // লিস্ট রিফ্রেশ করা
          await _fetchClassesFromSupabase();

          setState(() {
            _selectedClass = newClassName;
          });
          _validateForm();

          Get.back();
          Get.snackbar(
            "সফল",
            "'$newClassName' সফলভাবে যুক্ত করা হয়েছে।",
            backgroundColor: Colors.green,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
        } catch (e) {
          Get.snackbar(
            "ত্রুটি",
            "ক্লাস সংরক্ষণ করতে সমস্যা হয়েছে: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // ডিভাইস স্টোরেজ থেকে ছবি সিলেক্ট করা
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      Get.snackbar(
        "ছবি নির্বাচন ত্রুটি",
        "গ্যালারি থেকে ছবি লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // সাবমিটের সময় খালি ফিল্ড চেক করা
  void _handleAttemptSubmit() {
    List<String> missingFields = [];

    if (_nameController.text.trim().isEmpty)
      missingFields.add('শিক্ষার্থীর নাম');
    if (_fatherNameController.text.trim().isEmpty)
      missingFields.add('পিতার নাম');
    if (_selectedClass == null || _selectedClass == '+ নতুন শ্রেণি যোগ করুন')
      missingFields.add('শ্রেণি');
    if (_rollController.text.trim().isEmpty) missingFields.add('রোল নাম্বার');
    if (_phoneController.text.trim().isEmpty)
      missingFields.add('মোবাইল নাম্বার');
    if (_feeController.text.trim().isEmpty) missingFields.add('মাসিক বেতন');
    if (_addressController.text.trim().isEmpty)
      missingFields.add('পূর্ণ ঠিকানা');

    if (missingFields.isNotEmpty) {
      Get.snackbar(
        "তথ্য অসম্পূর্ণ!",
        "দয়া করে নিচের ঘরগুলো পূরণ করুন:\n• ${missingFields.join('\n• ')}",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // ডুপ্লিকেট রোল ডায়ালগ
  void _showDuplicateRollDialog(Map<String, dynamic> existingStudent) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('রোল ইতিমধ্যে বিদ্যমান!', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'এই প্রতিষ্ঠানে এই শ্রেণিতে এই রোল নম্বরের একজন শিক্ষার্থী ইতিমধ্যেই রেজিস্টার্ড রয়েছে:',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'নাম: ${existingStudent['name'] ?? 'প্রযোজ্য নয়'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('শ্রেণি: ${existingStudent['class'] ?? 'প্রযোজ্য নয়'}'),
                  const SizedBox(height: 4),
                  Text('রোল: ${existingStudent['roll'] ?? 'প্রযোজ্য নয়'}'),
                  const SizedBox(height: 4),
                  Text('ফোন: ${existingStudent['phone'] ?? 'প্রযোজ্য নয়'}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Get.back(),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  // ইউনিক পাসওয়ার্ড জেনারেটর
  Future<String> _generateUniquePassword(
    SupabaseClient supabase,
    String fullName,
  ) async {
    String cleanName = fullName.trim();
    String prefix = "ST";

    if (cleanName.isNotEmpty) {
      List<String> words = cleanName.split(' ');
      if (words.isNotEmpty && words[0].length >= 2) {
        prefix = words[0].substring(0, 2).toUpperCase();
      } else if (cleanName.length >= 2) {
        prefix = cleanName.substring(0, 2).toUpperCase();
      } else {
        prefix = cleanName.toUpperCase();
      }
    }

    final random = Random();
    bool isUnique = false;
    String finalPassword = "";

    while (!isUnique) {
      int randomDigits = 1000 + random.nextInt(9000);
      finalPassword = "$prefix$randomDigits";

      final existing = await supabase
          .from('students')
          .select('custom_password')
          .eq('custom_password', finalPassword)
          .maybeSingle();

      if (existing == null) isUnique = true;
    }

    return finalPassword;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _rollController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('নতুন শিক্ষার্থী ভর্তি'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ছবি আপলোড সেকশন
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.teal.shade100,
                        backgroundImage: _selectedImage != null
                            ? FileImage(_selectedImage!)
                            : null,
                        child: _selectedImage == null
                            ? Icon(
                                Icons.person,
                                size: 65,
                                color: Colors.teal.shade800,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.teal,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'ছবি পরিবর্তন করতে ট্যাপ করুন',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // শিক্ষার্থীর নাম
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'শিক্ষার্থীর নাম*',
                  prefixIcon: const Icon(Icons.person, color: Colors.teal),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),

              // পিতার নাম
              TextFormField(
                controller: _fatherNameController,
                decoration: InputDecoration(
                  labelText: 'পিতার নাম*',
                  prefixIcon: const Icon(
                    Icons.family_restroom,
                    color: Colors.teal,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),

              // সুপাবেস থেকে ডায়নামিক শ্রেণি ড্রপডাউন
              _isClassLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : DropdownButtonFormField<String>(
                      value: _selectedClass,
                      decoration: InputDecoration(
                        labelText: 'শ্রেণি নির্বাচন করুন*',
                        prefixIcon: const Icon(
                          Icons.class_,
                          color: Colors.teal,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        ..._classList.map((cls) {
                          return DropdownMenuItem<String>(
                            value: cls['class_name'].toString(),
                            child: Text(cls['class_name'].toString()),
                          );
                        }),
                        const DropdownMenuItem<String>(
                          value: '+ নতুন শ্রেণি যোগ করুন',
                          child: Text(
                            '+ নতুন শ্রেণি যোগ করুন',
                            style: TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue == '+ নতুন শ্রেণি যোগ করুন') {
                          _showAddClassDialog();
                        } else {
                          setState(() {
                            _selectedClass = newValue;
                          });
                          _validateForm();
                        }
                      },
                    ),
              const SizedBox(height: 15),

              // রোল নাম্বার
              TextFormField(
                controller: _rollController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'রোল নাম্বার*',
                  prefixIcon: const Icon(
                    Icons.format_list_numbered,
                    color: Colors.teal,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),

              // মোবাইল নাম্বার
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'মোবাইল নাম্বার*',
                  prefixIcon: const Icon(Icons.phone, color: Colors.teal),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),

              // মাসিক বেতন
              TextFormField(
                controller: _feeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'মাসিক বেতন (টাকা)*',
                  prefixIcon: const Icon(
                    Icons.currency_exchange,
                    color: Colors.teal,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),

              // ঠিকানা
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'পূর্ণ ঠিকানা*',
                  prefixIcon: const Icon(Icons.location_on, color: Colors.teal),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 30),

              // স্মার্ট সাবমিট বাটন
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFormValid
                        ? Colors.teal
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: _isFormValid ? 3 : 0,
                  ),
                  onPressed: _isLoading
                      ? null
                      : (_isFormValid
                            ? _saveStudentData
                            : _handleAttemptSubmit),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isFormValid
                              ? 'ভর্তি নিশ্চিত করুন'
                              : 'সকল তথ্য পূরণ করুন',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ছাত্র ডেটাবেসে সেভ করার লজিক
  Future<void> _saveStudentData() async {
    if (_selectedClass == null || _selectedClass == '+ নতুন শ্রেণি যোগ করুন') {
      Get.snackbar(
        "ত্রুটি",
        "দয়া করে আগে সঠিক শ্রেণি নির্বাচন করুন",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUserEmail = supabase.auth.currentUser?.email;

      if (currentUserEmail == null) {
        setState(() => _isLoading = false);
        Get.snackbar(
          "ত্রুটি",
          "ব্যবহারকারী লগইন করা নেই!",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final userData = await supabase
          .from('users')
          .select('academy_id')
          .eq('email', currentUserEmail!)
          .single();

      final academyId = userData['academy_id'];
      final enteredRoll = _rollController.text.trim();
      final selectedClassStr = _selectedClass!;
      final studentName = _nameController.text.trim();

      // ডুপ্লিকেট রোল চেক
      final List<dynamic> existingRecords = await supabase
          .from('students')
          .select('name, class, roll, phone')
          .eq('academy_id', academyId)
          .eq('class', selectedClassStr)
          .eq('roll', enteredRoll);

      if (existingRecords.isNotEmpty) {
        setState(() => _isLoading = false);
        final existingStudent = existingRecords.first as Map<String, dynamic>;
        _showDuplicateRollDialog(existingStudent);
        return;
      }

      // ছবি আপলোড
      String? uploadedImageUrl;
      if (_selectedImage != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final path = 'student_photos/$fileName';

        await supabase.storage
            .from('student_photos')
            .upload(path, _selectedImage!);
        uploadedImageUrl = supabase.storage
            .from('student_photos')
            .getPublicUrl(path);
      }

      // ইউনিক পাসওয়ার্ড জেনারেট
      final String generatedPassword = await _generateUniquePassword(
        supabase,
        studentName,
      );

      // স্টুডেন্ট ইনসার্ট
      await supabase.from('students').insert({
        'academy_id': academyId,
        'name': studentName,
        'father_name': _fatherNameController.text.trim(),
        'class': selectedClassStr,
        'roll': enteredRoll,
        'phone': _phoneController.text.trim(),
        'monthly_fee': double.tryParse(_feeController.text.trim()) ?? 0.0,
        'address': _addressController.text.trim(),
        'custom_password': generatedPassword,
        'image_url': uploadedImageUrl,
      });

      Get.back();
      Get.snackbar(
        "সফল",
        "শিক্ষার্থী সফলভাবে ভর্তি হয়েছে!\nপাসওয়ার্ড: $generatedPassword",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
