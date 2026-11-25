import 'package:academy_management/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperProfileView extends StatelessWidget {
  const DeveloperProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    const String developerEmail = 'abbas.zhsust@gmail.com';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'ডেভেলপারের তথ্য',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ১. টপ গ্রুডিয়েন্ট হেডার সেকশন
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal, Color(0xFF004D40)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              padding: EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              child: Column(
                children: [
                  // প্রোফাইল ছবি উইথ বর্ডার ও শ্যাডো
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surfaceOf(context), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: AppTheme.surfaceOf(context),
                      backgroundImage: AssetImage('assets/images/abbas.jpg'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Abbas Uddin',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Full-Stack Developer & Software Engineer',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // ২. ইনফরমেশন ও কন্টাক্ট সেকশন
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'প্রোফাইল বিবরণী',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.mutedOf(context),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // যোগাযোগ কার্ড
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // ইমেইল সেকশন
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.tileOf(context, Colors.teal),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.email,
                                color: Colors.teal,
                              ),
                            ),
                            title: Text(
                              'ইমেইল অ্যাড্রেস',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedOf(context),
                              ),
                            ),
                            subtitle: InkWell(
                              onTap: () async {
                                final Uri emailUri = Uri(
                                  scheme: 'mailto',
                                  path: developerEmail,
                                  query:
                                      'subject=Developer Support & Feedback&body=Hi Abbas, I want to contact you regarding the Academy Management App.',
                                );
                                await launchUrl(emailUri);
                              },
                              child: Text(
                                developerEmail,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          Divider(height: 20),

                          // দক্ষতা সেকশন
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.tileOf(context, Colors.teal),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.code, color: Colors.teal),
                            ),
                            title: Text(
                              'মূল দক্ষতা',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedOf(context),
                              ),
                            ),
                            subtitle: Text(
                              'Flutter, Supabase, Firebase, Web & Mobile App Development',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.inkOf(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // সরাসরি ইমেইল করার আকর্ষণীয় বাটন (CTA Button)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final Uri emailUri = Uri(
                          scheme: 'mailto',
                          path: developerEmail,
                          query:
                              'subject=Developer Support & Feedback&body=Hi Abbas, I want to contact you regarding the Academy Management App.',
                        );
                        await launchUrl(emailUri);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.send, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'সরাসরি ইমেইল পাঠান',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
