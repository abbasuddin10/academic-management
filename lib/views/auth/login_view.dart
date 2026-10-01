import 'package:academy_management/views/auth/StudentLoginWidget.dart';
import 'package:academy_management/views/auth/TeacherLoginWidget.dart';
import 'package:flutter/material.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  int selectedRoleIndex = 0; // 0 = শিক্ষক/অ্যাডমিন, 1 = শিক্ষার্থী

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // লোগো বা আইকন
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: selectedRoleIndex == 0
                          ? Colors.teal.shade50
                          : Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      selectedRoleIndex == 0
                          ? Icons.school_rounded
                          : Icons.child_care_rounded,
                      size: 60,
                      color: selectedRoleIndex == 0
                          ? Colors.teal
                          : Colors.indigo,
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // ডাইনামিক টাইটেল (শিক্ষার্থী হলে Student Manager দেখাবে)
                Text(
                  selectedRoleIndex == 0
                      ? 'Academy Manager'
                      : 'Student Manager',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'আপনার রোল সিলেক্ট করে লগইন করুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 25),

                // কাস্টম বাটন লেআউট (বাটনগুলো যেন গায়ে গায়ে লেগে না থাকে)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      // শিক্ষক / অ্যাডমিন বাটন
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => selectedRoleIndex = 0),
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              color: selectedRoleIndex == 0
                                  ? Colors.teal
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 18,
                                  color: selectedRoleIndex == 0
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'শিক্ষক / অ্যাডমিন',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selectedRoleIndex == 0
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ), // দুটি বাটনের মাঝখানে ফাঁকা জায়গা
                      // শিক্ষার্থী বাটন
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => selectedRoleIndex = 1),
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              color: selectedRoleIndex == 1
                                  ? Colors.indigo
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.child_care,
                                  size: 18,
                                  color: selectedRoleIndex == 1
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'শিক্ষার্থী',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selectedRoleIndex == 1
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // রোল অনুযায়ী উইজেট শো করা (ValueKey সহ)
                if (selectedRoleIndex == 0)
                  const TeacherLoginWidget(key: ValueKey('teacher'))
                else
                  const StudentLoginWidget(key: ValueKey('student')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
