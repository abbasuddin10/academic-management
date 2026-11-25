import 'package:academy_management/services/password_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/views/teacher/teacher_home_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart'; // প্যাকেজ যুক্ত করা হলো
import 'academy_register_view.dart';
import '../dashboard/shared_dashboard.dart';

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

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    if (!_teacherFormKey.currentState!.validate()) return;
    if (isTeacherLoading) return;

    setState(() => isTeacherLoading = true);

    final supabase = Supabase.instance.client;
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    try {
      // Authoritative role lookup happens BEFORE any privileged routing.
      final userRow = await SessionService.fetchUserRow(email);

      if (!mounted) return;

      if (userRow == null) {
        _showInvalidCredentials();
        return;
      }

      final role = userRow['role']?.toString() ?? '';
      final fullName =
          (userRow['full_name'] ?? userRow['name'] ?? 'শিক্ষক').toString();

      if (role == 'super_admin') {
        // Admin access requires a real Supabase Auth session AND a database
        // role of super_admin. A successful auth call by itself is not enough.
        try {
          await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } catch (_) {
          if (mounted) _showInvalidCredentials();
          return;
        }

        if (!mounted) return;

        final verifiedRow = await SessionService.fetchUserRow(email);
        if (verifiedRow == null || verifiedRow['role'] != 'super_admin') {
          await supabase.auth.signOut();
          if (mounted) _showInvalidCredentials();
          return;
        }

        if (!mounted) return;
        Get.snackbar(
          "স্বাগতম, $fullName!",
          "সুপার এডমিন হিসেবে সফলভাবে লগইন হয়েছে।",
          backgroundColor: Colors.indigo,
          colorText: Colors.white,
        );
        Get.offAll(
          () => SharedDashboard(
            role: 'super_admin',
            userName: fullName,
            currentUserId: verifiedRow['id']?.toString(),
          ),
        );
        return;
      }

      if (SessionService.isTeacherRole(role)) {
        final storedPassword = userRow['password']?.toString() ?? '';

        if (!PasswordService.verify(password, storedPassword)) {
          if (mounted) {
            Get.snackbar(
              "ভুল পাসওয়ার্ড!",
              "শিক্ষকের পাসওয়ার্ড সঠিক নয়।",
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
          return;
        }

        // Transparently upgrade legacy plaintext records to PBKDF2 hashes.
        // Best-effort only — a failed write must not block a valid login.
        if (PasswordService.needsUpgrade(storedPassword)) {
          try {
            await supabase
                .from('users')
                .update({'password': PasswordService.hash(password)})
                .eq('id', userRow['id']);
          } catch (e) {
            debugPrint('Legacy password upgrade skipped: $e');
          }
        }

        // Give the teacher a real (anonymous) Supabase session so RLS can
        // scope every subsequent query to this academy.
        final sessionEstablished = await SessionService.startAppSession(
          academyId: userRow['academy_id']?.toString() ?? '',
          role: role,
          displayName: fullName,
          readerKey: SessionService.readerKeyFor(
            role: role,
            userId: userRow['id']?.toString() ?? '',
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
        await prefs.setBool(SessionService.teacherLoggedInKey, true);
        await prefs.setString(SessionService.teacherEmailKey, email);
        await prefs.setString(
          SessionService.teacherIdKey,
          userRow['id'].toString(),
        );
        await prefs.setString(
          SessionService.academyIdKey,
          userRow['academy_id']?.toString() ?? '',
        );

        // FCM token update is non-blocking.
        try {
          final String? fcmToken =
              await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await supabase
                .from('users')
                .update({'fcm_token': fcmToken})
                .eq('email', email);
          }
        } catch (e) {
          debugPrint('FCM Token Error: $e');
        }

        if (!mounted) return;
        Get.snackbar(
          "স্বাগতম, $fullName!",
          "শিক্ষক হিসেবে সফলভাবে লগইন হয়েছে।",
          backgroundColor: Colors.teal,
          colorText: Colors.white,
        );
        Get.offAll(() => TeacherHomeView(userName: fullName));
        return;
      }

      // Unknown/unauthorised role — never grant access.
      _showInvalidCredentials();
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) {
        Get.snackbar(
          "ত্রুটি!",
          "লগইন করার সময় সমস্যা হয়েছে। আবার চেষ্টা করুন।",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => isTeacherLoading = false);
      }
    }
  }

  void _showInvalidCredentials() {
    Get.snackbar(
      "লগইন ব্যর্থ!",
      "ইমেইল অথবা পাসওয়ার্ড সঠিক নয়।",
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
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
