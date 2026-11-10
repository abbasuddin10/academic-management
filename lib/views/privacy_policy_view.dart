import 'package:flutter/material.dart';

class PrivacyPolicyView extends StatelessWidget {
  const PrivacyPolicyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // হেডার সেকশন
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.privacy_tip, color: Colors.teal, size: 40),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Privacy Matters',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Last updated: November 2026',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // মূল কন্টেন্ট কার্ডসমূহ
            _buildPolicyCard(
              title: '1. Information We Collect',
              icon: Icons.data_usage,
              content:
                  'We collect information necessary to provide a seamless academy management experience, including student records, teacher profiles, and financial logs entered by authorized users.',
            ),
            const SizedBox(height: 12),

            _buildPolicyCard(
              title: '2. Use of Advertisements',
              icon: Icons.ads_click,
              content:
                  'We use Google AdMob to display advertisements in this app. AdMob may use device identifiers and cookies to serve personalized ads based on user interactions.',
            ),
            const SizedBox(height: 12),

            _buildPolicyCard(
              title: '3. Data Security',
              icon: Icons.security,
              content:
                  'All data processed within the application is securely stored using industry-standard protocols (such as Supabase and Firebase) to protect against unauthorized access.',
            ),
            const SizedBox(height: 12),

            _buildPolicyCard(
              title: '4. Third-Party Services',
              icon: Icons.link,
              content:
                  'Our application integrates trusted third-party services like Google Firebase and Supabase for authentication, cloud storage, and push notifications.',
            ),
            const SizedBox(height: 12),

            _buildPolicyCard(
              title: '5. Contact Us',
              icon: Icons.contact_support,
              content:
                  'If you have any questions or suggestions regarding our Privacy Policy, please feel free to contact us through the developer support section.',
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // স্মার্ট কার্ড উইজেট ডিজাইন জেনারেটর
  Widget _buildPolicyCard({
    required String title,
    required IconData icon,
    required String content,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.teal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
