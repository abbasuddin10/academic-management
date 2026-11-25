import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/password_service.dart';
import 'package:academy_management/services/fcm_token_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:academy_management/views/student/student_home_view.dart';

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
  bool _obscurePassword = true; // পাসওয়ার্ড হাইড বা শো করার স্টেট

  List<Map<String, dynamic>> academyList = [];
  bool isAcademyLoading = true;
  String? selectedAcademyId;

  List<String> classList = [];
  bool isClassLoading = false;

  @override
  void dispose() {
    academyController.dispose();
    classController.dispose();
    rollController.dispose();
    pinController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        fetchAcademies();
      }
    });
  }

  // একাডেমি ফেচ করা এবং ক্র্যাশ এড়াতে সেফ কাস্টিং
  Future<void> fetchAcademies() async {
    if (!mounted) return;
    try {
      final academies = await AcademyRepository().fetchAll().timeout(
        const Duration(seconds: 10),
      );

      if (!mounted) return;

      setState(() {
        academyList = academies.map((academy) => academy.toMap()).toList();
        isAcademyLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching academies: $e");
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
      final response = await supabase.rpc(
        'public_academy_classes',
        params: {'p_academy_id': academyId},
      );

      if (!mounted) return;

      Set<String> uniqueClasses = {};
      if (response is List) {
        for (var item in response) {
          final value = item is Map ? item['class'] : item;
          if (value != null) {
            uniqueClasses.add(value.toString().trim());
          }
        }
      }

      setState(() {
        classList = uniqueClasses.toList();
        isClassLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching classes: $e");
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

      final loginResult = await supabase.rpc(
        'lookup_student_for_login',
        params: {
          'p_academy_id': selectedAcademyId!,
          'p_class': className,
          'p_roll': roll,
        },
      );

      if (!mounted) return;

      final studentResponse = (loginResult is List && loginResult.isNotEmpty)
          ? Map<String, dynamic>.from(loginResult.first as Map)
          : null;

      // Password verification is done locally so only a hash is ever stored.
      if (studentResponse != null &&
          PasswordService.verify(
            pin,
            studentResponse['custom_password']?.toString(),
          )) {
        String studentName = studentResponse['name'] ?? '';
        String academyName = academyController.text.trim();
        String studentId = studentResponse['id'] ?? '';

        // Transparently upgrade legacy plaintext PINs to PBKDF2 hashes.
        // This is best-effort: a failed write (e.g. RLS) must not block login.
        if (PasswordService.needsUpgrade(
          studentResponse['custom_password']?.toString(),
        )) {
          try {
            await supabase
                .from('students')
                .update({'custom_password': PasswordService.hash(pin)})
                .eq('id', studentId);
          } catch (e) {
            debugPrint('Legacy PIN upgrade skipped: $e');
          }
        }

        // Give the student a real (anonymous) Supabase session so RLS can
        // scope every subsequent query to this academy.
        final sessionEstablished = await SessionService.startAppSession(
          academyId: selectedAcademyId!,
          role: 'student',
          displayName: studentName,
          readerKey: SessionService.readerKeyFor(
            role: 'student',
            userId: studentId,
          ),
        );
        if (!sessionEstablished && mounted) {
          Get.snackbar(
            'সতর্কতা',
            'সিকিউর সেশন তৈরি করা যায়নি। অ্যাডমিনের সাথে যোগাযোগ করুন।',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(SessionService.studentLoggedInKey, true);
        await prefs.setString(SessionService.studentNameKey, studentName);
        await prefs.setString(SessionService.studentAcademyKey, academyName);
        await prefs.setString(SessionService.studentClassKey, className);
        await prefs.setString(SessionService.studentRollKey, roll);
        await prefs.setString(
          SessionService.studentAcademyIdKey,
          selectedAcademyId!,
        );
        await prefs.setString(SessionService.studentIdKey, studentId);

        // Register only AFTER the session keys above are persisted — syncNow()
        // resolves the student from these prefs and bails out if they are still
        // empty (as happened when this call ran before the writes).
        unawaited(FcmTokenService.syncNow());

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

  // একাডেমি সার্চ ডায়ালগ (ক্র্যাশ ফ্রি ও স্মার্ট ইউআই)
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

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.5,
                child: Column(
                  children: [
                    const Text(
                      "একাডেমি বেছে নিন",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'একাডেমির নাম খুঁজুন...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.indigo,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 10,
                        ),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          tempSearchList = academyList
                              .where(
                                (item) => (item['academy_name'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains(value.toLowerCase()),
                              )
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: tempSearchList.isEmpty
                          ? const Center(child: Text("কোন একাডেমি পাওয়া যায়নি"))
                          : ListView.builder(
                              itemCount: tempSearchList.length,
                              itemBuilder: (context, index) {
                                final academy = tempSearchList[index];
                                final String academyName =
                                    academy['academy_name']?.toString() ?? '';
                                final String? address = academy['address']
                                    ?.toString();
                                final String? logoUrl = academy['logo_url']
                                    ?.toString();
                                final String academyId =
                                    academy['id']?.toString() ?? '';

                                return ListTile(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTheme.borderOf(context),
                                    backgroundImage:
                                        (logoUrl != null &&
                                            logoUrl.trim().isNotEmpty)
                                        ? NetworkImage(logoUrl.trim())
                                        : null,
                                    child:
                                        (logoUrl == null ||
                                            logoUrl.trim().isEmpty)
                                        ? const Icon(
                                            Icons.business,
                                            color: Colors.indigo,
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    academyName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle:
                                      (address != null &&
                                          address.trim().isNotEmpty)
                                      ? Text(
                                          address.trim(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.mutedOf(context),
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      academyController.text = academyName;
                                      selectedAcademyId = academyId;
                                    });
                                    Get.back();
                                    fetchClassesByAcademyId(academyId);
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
        ),
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

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.4,
                child: Column(
                  children: [
                    const Text(
                      "ক্লাস বেছে নিন",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isClassLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.indigo,
                              ),
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
                    ),
                  ],
                ),
              );
            },
          ),
        ),
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
                    : Icon(Icons.arrow_drop_down),
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
                      : AppTheme.inkOf(context),
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
                      : AppTheme.inkOf(context),
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

          // পিন / পাসওয়ার্ড (এখানে পাসওয়ার্ড শো/হাইড করার আইকন যুক্ত করা হয়েছে)
          TextFormField(
            controller: pinController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'পাসওয়ার্ড / পিন',
              prefixIcon: const Icon(Icons.lock, color: Colors.indigo),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.indigo,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
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
