import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/views/auth/student_login_widget.dart';
import 'package:academy_management/views/auth/teacher_login_widget.dart';
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
      backgroundColor: AppTheme.altSurfaceOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // লোগো বা আইকন
                Center(
                  child: Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: selectedRoleIndex == 0
                          ? AppTheme.tileOf(context, Colors.teal)
                          : AppTheme.tileOf(context, Colors.indigo),
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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'আপনার রোল সিলেক্ট করে লগইন করুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                SizedBox(height: 25),

                // কাস্টম বাটন লেআউট (বাটনগুলো যেন গায়ে গায়ে লেগে না থাকে)
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.borderOf(context),
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
                                      : AppTheme.inkOf(context),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'শিক্ষক / অ্যাডমিন',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selectedRoleIndex == 0
                                        ? Colors.white
                                        : AppTheme.inkOf(context),
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
                                      : AppTheme.inkOf(context),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'শিক্ষার্থী',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selectedRoleIndex == 1
                                        ? Colors.white
                                        : AppTheme.inkOf(context),
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
