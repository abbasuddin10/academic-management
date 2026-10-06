import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart'; // প্যাকেজ যুক্ত করা হলো
import 'academy_register_view.dart';
import '../dashboard/shared_dashboard.dart';
import '../dashboard/teacher_home_view.dart';

class TeacherLoginWidget extends StatefulWidget {
  const TeacherLoginWidget({super.key});

  @override
  State<TeacherLoginWidget> createState() => _TeacherLoginWidgetState();
}

class _TeacherLoginWidgetState extends State<TeacherLoginWidget> {
  final _teacherFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isTeacherLoading = false;
  bool _obscurePassword = true; // পাসওয়ার্ড হাইড বা শো করার স্টেট

  Future<void> loginUser() async {
    if (!_teacherFormKey.currentState!.validate()) return;
    if (isTeacherLoading) return;

    setState(() => isTeacherLoading = true);

    try {
      final supabase = Supabase.instance.client;
      String email = emailController.text.trim();
      String password = passwordController.text.trim();

      // ১. প্রথমে সুপার এডমিন চেক (Supabase Auth)
      try {
        final AuthResponse authRes = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (authRes.user != null) {
          String adminName =
              authRes.user!.userMetadata?['full_name'] ?? 'সুপার এডমিন';

          // এডমিনের ক্ষেত্রেও চাইলে SharedPreferences সেভ করতে পারেন, অথবা সরাসরি রিডাইরেক্ট:
          if (!mounted) return;
          Get.snackbar(
            "স্বাগতম, $adminName!",
            "সুপার এডমিন হিসেবে সফলভাবে লগইন হয়েছে।",
            backgroundColor: Colors.indigo,
            colorText: Colors.white,
          );
          Get.offAll(
            () => SharedDashboard(role: 'super_admin', userName: adminName),
          );
          return;
        }
      } catch (authError) {
        print("Not an admin, checking teacher table: $authError");
      }

      // ২. শিক্ষক চেক (users টেবিল থেকে)
      final teacherResponse = await supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (teacherResponse != null) {
        String dbPassword = teacherResponse['password'] ?? '';
        String fullName =
            teacherResponse['full_name'] ?? teacherResponse['name'] ?? 'শিক্ষক';

        if (dbPassword != password) {
          if (!mounted) return;
          Get.snackbar(
            "ভুল পাসওয়ার্ড!",
            "শিক্ষকের পাসওয়ার্ড সঠিক নয়।",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          setState(() => isTeacherLoading = false);
          return;
        }

        // গুরুত্বপূর্ণ: সফল লগইনের পর SharedPreferences-এ ইমেইল এবং লগইন স্ট্যাটাস সেভ করে রাখা
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_teacher_logged_in', true);
        await prefs.setString('teacher_email', email);

        // ফায়ারবেস টোকেন আপডেট (নন-ব্লকিং)
        try {
          String? fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await supabase
                .from('users')
                .update({'fcm_token': fcmToken})
                .eq('email', email);
          }
        } catch (e) {
          print("FCM Token Error: $e");
        }

        if (!mounted) return;

        Get.snackbar(
          "স্বাগতম, $fullName!",
          "শিক্ষক হিসেবে সফলভাবে লগইন হয়েছে।",
          backgroundColor: Colors.teal,
          colorText: Colors.white,
        );

        // ডাটাবেজের সঠিক নামটি পাস করা হলো
        Get.offAll(() => TeacherHomeView(userName: fullName));
        return;
      }

      if (!mounted) return;
      Get.snackbar(
        "লগইন ব্যর্থ!",
        "ইমেইল অথবা পাসওয়ার্ড সঠিক নয়।",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } catch (e) {
      print("Login Supabase Error: $e");
      if (!mounted) return;
      Get.snackbar(
        "ত্রুটি!",
        "লগইন করার সময় সমস্যা হয়েছে: ${e.toString()}",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => isTeacherLoading = false);
      }
    }
  }

  // পাসওয়ার্ড রিসেট ডায়ালগ
  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();
    bool isResetLoading = false;

    Get.defaultDialog(
      title: "পাসওয়ার্ড পুনরুদ্ধার",
      content: StatefulBuilder(
        builder: (context, setStateDialog) {
          return SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "আপনার রেজিস্টার্ড ইমেইলটি লিখুন।",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: resetEmailController,
                  decoration: InputDecoration(
                    labelText: 'ইমেইল এড্রেস',
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.teal,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isResetLoading
                        ? null
                        : () async {
                            String email = resetEmailController.text.trim();
                            if (email.isEmpty) return;
                            setStateDialog(() => isResetLoading = true);
                            try {
                              final supabase = Supabase.instance.client;
                              await supabase.auth.resetPasswordForEmail(email);
                              Get.back();
                              Get.snackbar(
                                "সফল",
                                "রিসেট লিংক পাঠানো হয়েছে",
                                backgroundColor: Colors.teal,
                                colorText: Colors.white,
                              );
                            } catch (e) {
                              Get.snackbar(
                                "ত্রুটি",
                                "ইমেইল পাঠানো যায়নি",
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            } finally {
                              if (context.mounted) {
                                setStateDialog(() => isResetLoading = false);
                              }
                            }
                          },
                    child: isResetLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('রিসেট লিংক পাঠান'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _teacherFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: emailController,
            decoration: InputDecoration(
              labelText: 'অফিসিয়াল ইমেইল',
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.teal),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (v) => v!.isEmpty ? 'ইমেইল দিন' : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'পাসওয়ার্ড',
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.teal),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.teal,
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
            validator: (v) => v!.isEmpty ? 'পাসওয়ার্ড দিন' : null,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: const Text(
                'পাসওয়ার্ড ভুলে গেছেন?',
                style: TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: isTeacherLoading ? null : loginUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isTeacherLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'লগইন করুন (শিক্ষক/অ্যাডমিন)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Get.to(() => const AcademyRegisterView()),
            icon: const Icon(Icons.add_business_rounded, color: Colors.teal),
            label: const Text(
              'নতুন একাডেমি রেজিস্টার করুন',
              style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.teal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
