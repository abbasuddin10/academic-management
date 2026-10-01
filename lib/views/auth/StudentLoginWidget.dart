import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:academy_management/views/dashboard/student_home_view.dart';

class StudentLoginWidget extends StatefulWidget {
  const StudentLoginWidget({super.key});

  @override
  State<StudentLoginWidget> createState() => _StudentLoginWidgetState();
}

class _StudentLoginWidgetState extends State<StudentLoginWidget> {
  final _studentFormKey = GlobalKey<FormState>();
  final TextEditingController academyController = TextEditingController();
  final TextEditingController classController = TextEditingController();
  final TextEditingController rollController = TextEditingController();
  final TextEditingController pinController = TextEditingController();
  bool isStudentLoading = false;

  List<Map<String, dynamic>> academyList = [];
  bool isAcademyLoading = true;
  String? selectedAcademyId;

  List<String> classList = [];
  bool isClassLoading = false;

  @override
  void initState() {
    super.initState();
    // মাইক্রোটাস্ক বা একটু ডিলে দিয়ে কল করলে টগল করার সময় আর ল্যাগ করবে না
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        fetchAcademies();
      }
    });
  }

  // একাডেমি ফেচ করা (টাইমআউট হ্যান্ডলিং সহ)
  Future<void> fetchAcademies() async {
    if (!mounted) return;
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('academies')
          .select('id, academy_name')
          .timeout(const Duration(seconds: 10)); // অতিরিক্ত সেফটির জন্য টাইমআউট

      if (!mounted) return;

      setState(() {
        academyList = List<Map<String, dynamic>>.from(response);
        isAcademyLoading = false;
      });
    } catch (e) {
      print("Error fetching academies: $e");
      if (!mounted) return;
      setState(() {
        isAcademyLoading = false;
      });
      Get.snackbar(
        "সংযোগের সমস্যা",
        "একাডেমি তালিকা লোড করা যায়নি। ইন্টারনেট কানেকশন চেক করুন।",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // নির্দিষ্ট একাডেমির ক্লাস ফেচ করা
  Future<void> fetchClassesByAcademyId(String academyId) async {
    if (!mounted) return;
    setState(() {
      isClassLoading = true;
      classList.clear();
      classController.clear();
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('students')
          .select('class')
          .eq('academy_id', academyId);

      if (!mounted) return;

      Set<String> uniqueClasses = {};
      for (var item in (response as List)) {
        if (item['class'] != null) {
          uniqueClasses.add(item['class'].toString().trim());
        }
      }

      setState(() {
        classList = uniqueClasses.toList();
        isClassLoading = false;
      });
    } catch (e) {
      print("Error fetching classes: $e");
      if (!mounted) return;
      setState(() {
        isClassLoading = false;
      });
    }
  }

  // স্টুডেন্ট লগইন লজিক
  Future<void> loginStudent() async {
    if (!_studentFormKey.currentState!.validate()) return;
    if (selectedAcademyId == null) {
      Get.snackbar(
        "ত্রুটি!",
        "দয়া করে একাডেমি সিলেক্ট করুন।",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => isStudentLoading = true);

    try {
      final supabase = Supabase.instance.client;
      String className = classController.text.trim();
      String roll = rollController.text.trim();
      String pin = pinController.text.trim();

      final studentResponse = await supabase
          .from('students')
          .select()
          .eq('academy_id', selectedAcademyId!)
          .eq('class', className)
          .eq('roll', roll)
          .eq('custom_password', pin)
          .maybeSingle();

      if (!mounted) return;

      if (studentResponse != null) {
        String studentName = studentResponse['name'];
        String academyName = academyController.text.trim();
        String studentId = studentResponse['id'];

        // ফায়ারবেস থেকে FCM টোকেন নিয়ে students টেবিলে আপডেট করা
        try {
          String? fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await supabase
                .from('students')
                .update({'fcm_token': fcmToken})
                .eq('id', studentId);
          }
        } catch (e) {
          print("Student token error: $e");
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_student_logged_in', true);
        await prefs.setString('student_name', studentName);
        await prefs.setString('student_academy', academyName);
        await prefs.setString('student_class', className);
        await prefs.setString('student_roll', roll);

        Get.offAll(
          () => StudentHomeView(
            studentName: studentName,
            academyName: academyName,
            className: className,
            roll: roll,
          ),
        );
      } else {
        Get.snackbar(
          "লগইন ব্যর্থ!",
          "তথ্যগুলো সঠিক নয়। পিন পুনরায় চেক করুন।",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        "ত্রুটি!",
        "সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => isStudentLoading = false);
      }
    }
  }

  // একাডেমি সার্চ ডায়ালগ (অফিসিয়াল গেট ডায়ালগ অপ্টিমাইজড)
  void _showAcademySearchDialog() {
    if (academyList.isEmpty) {
      Get.snackbar(
        "সতর্কতা",
        "কোনো একাডেমি পাওয়া যায়নি বা লোড হচ্ছে...",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    List<Map<String, dynamic>> tempSearchList = List.from(academyList);

    Get.defaultDialog(
      title: "একাডেমি বেছে নিন",
      content: StatefulBuilder(
        builder: (context, setStateDialog) {
          return SizedBox(
            width: 320,
            height: 350,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'একাডেমির নাম খুঁজুন...',
                    prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) {
                    setStateDialog(() {
                      tempSearchList = academyList
                          .where(
                            (item) => item['academy_name']
                                .toString()
                                .toLowerCase()
                                .contains(value.toLowerCase()),
                          )
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: tempSearchList.length,
                    itemBuilder: (context, index) {
                      final academy = tempSearchList[index];
                      return ListTile(
                        title: Text(academy['academy_name']),
                        onTap: () {
                          setState(() {
                            academyController.text = academy['academy_name'];
                            selectedAcademyId = academy['id'];
                          });
                          Get.back();
                          fetchClassesByAcademyId(selectedAcademyId!);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ক্লাস সার্চ ডায়ালগ
  void _showClassSearchDialog() {
    if (selectedAcademyId == null) {
      Get.snackbar(
        "সতর্কতা",
        "আগে একাডেমি সিলেক্ট করুন!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    Get.defaultDialog(
      title: "ক্লাস বেছে নিন",
      content: StatefulBuilder(
        builder: (context, setStateDialog) {
          return SizedBox(
            width: 320,
            height: 300,
            child: isClassLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  )
                : classList.isEmpty
                ? const Center(
                    child: Text(
                      "এই একাডেমিতে কোনো ক্লাস পাওয়া যায়নি",
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: classList.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(classList[index]),
                        onTap: () {
                          setState(() {
                            classController.text = classList[index];
                          });
                          Get.back();
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _studentFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // একাডেমি ড্রপডাউন
          InkWell(
            onTap: _showAcademySearchDialog,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'প্রতিষ্ঠান বা একাডেমির নাম',
                prefixIcon: const Icon(Icons.business, color: Colors.indigo),
                suffixIcon: isAcademyLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.arrow_drop_down),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                academyController.text.isEmpty
                    ? (isAcademyLoading
                          ? 'লোড হচ্ছে...'
                          : 'একাডেমি সিলেক্ট করুন')
                    : academyController.text,
                style: TextStyle(
                  color: academyController.text.isEmpty
                      ? Colors.grey.shade600
                      : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),

          // ক্লাস ড্রপডাউন
          InkWell(
            onTap: _showClassSearchDialog,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'ক্লাস সিলেক্ট করুন',
                prefixIcon: const Icon(Icons.class_, color: Colors.indigo),
                suffixIcon: isClassLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.arrow_drop_down),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                classController.text.isEmpty
                    ? (selectedAcademyId == null
                          ? 'আগে একাডেমি সিলেক্ট করুন'
                          : (isClassLoading
                                ? 'ক্লাস লোড হচ্ছে...'
                                : 'ক্লাস সিলেক্ট করুন'))
                    : classController.text,
                style: TextStyle(
                  color: classController.text.isEmpty
                      ? Colors.grey.shade600
                      : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),

          // রোল নম্বর
          TextFormField(
            controller: rollController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'রোল নম্বর',
              prefixIcon: const Icon(
                Icons.format_list_numbered,
                color: Colors.indigo,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) => value!.isEmpty ? 'রোল নম্বর দিন' : null,
          ),
          const SizedBox(height: 15),

          // পিন / পাসওয়ার্ড
          TextFormField(
            controller: pinController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'পাসওয়ার্ড / পিন',
              prefixIcon: const Icon(Icons.lock, color: Colors.indigo),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) => value!.isEmpty ? 'পিন দিন' : null,
          ),
          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: isStudentLoading ? null : loginStudent,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isStudentLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'লগইন করুন (শিক্ষার্থী)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
