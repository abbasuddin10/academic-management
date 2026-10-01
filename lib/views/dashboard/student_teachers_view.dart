import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentTeachersView extends StatefulWidget {
  final String academyId;
  final String academyName;

  const StudentTeachersView({
    super.key,
    required this.academyId,
    required this.academyName,
  });

  @override
  State<StudentTeachersView> createState() => _StudentTeachersViewState();
}

class _StudentTeachersViewState extends State<StudentTeachersView> {
  bool isLoading = true;
  bool hasError = false;
  List<Map<String, dynamic>> staffList = [];

  @override
  void initState() {
    super.initState();
    fetchStaffAndAdmins();
  }

  // ব্যাকগ্রাউন্ডে ডাটা ফেচ করার ফাংশন
  Future<void> fetchStaffAndAdmins() async {
    try {
      setState(() {
        isLoading = true;
        hasError = false;
      });

      final supabase = Supabase.instance.client;

      // users টেবিল থেকে নির্দিষ্ট একাডেমির শিক্ষক এবং সুপার অ্যাডমিনদের ফেচ করা
      final response = await supabase
          .from('users')
          .select()
          .eq('academy_id', widget.academyId)
          .inFilter('role', ['teacher', 'super_admin']);

      if (!mounted) return;
      setState(() {
        staffList = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching staff: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  // কল করার আগে পপআপ দেখানোর ফাংশন
  void _showCallConfirmationDialog(String phoneNumber, String name) {
    if (phoneNumber.isEmpty || phoneNumber == 'মোবাইল নম্বর নেই') {
      Get.snackbar(
        'দুঃখিত',
        'এই ব্যবহারকারীর কোনো মোবাইল নম্বর যুক্ত করা নেই।',
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
      return;
    }

    Get.defaultDialog(
      title: "কল করার পূর্বে",
      titleStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      middleText:
          "দয়া করে উপযুক্ত সময়ে ($name-এর সাথে) যোগাযোগ করুন। "
          "তিনি ব্যস্ত থাকতে পারেন বা পাঠদান বা অন্য কাজে নিয়োজিত থাকতে পারেন। "
          "জরুরি প্রয়োজন ছাড়া অযথা কল করা থেকে বিরত থাকুন。\n\nআপনি কি কল করতে চান?",
      textConfirm: "হ্যাঁ, কল করুন",
      textCancel: "না",
      confirmTextColor: Colors.white,
      buttonColor: Colors.indigo,
      onConfirm: () {
        Get.back(); // পপআপ বন্ধ করা
        _makePhoneCall(phoneNumber);
      },
    );
  }

  // ডায়ালপ্যাডে ফোন নম্বর ওপেন করার ফাংশন
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        Get.snackbar('ত্রুটি', 'কল করা সম্ভব হচ্ছে না');
      }
    } catch (e) {
      print("Call error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'শিক্ষক ও প্রশাসকবৃন্দ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 60,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ইন্টারনেট কানেকশন চেক করুন অথবা ডাটা লোড করতে সমস্যা হচ্ছে।',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: fetchStaffAndAdmins,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 시도 (পুনরায় চেষ্টা করুন)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                staffList.isEmpty && !isLoading
                    ? const Center(
                        child: Text(
                          'এই মুহূর্তে কোনো শিক্ষক বা অ্যাডমিন সংযুক্ত নেই।',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: staffList.length,
                        itemBuilder: (context, index) {
                          final staff = staffList[index];
                          String name = staff['full_name'] ?? 'নামবিহীন';
                          String email = staff['email'] ?? 'ইমেইল নেই';
                          String phone = staff['phone'] ?? 'মোবাইল নম্বর নেই';
                          String role = staff['role'] ?? '';
                          String? photoUrl = staff['photo_url'];

                          // রোল অনুযায়ী ইউজার টাইপ নির্ধারণ
                          String roleDisplayName = role == 'super_admin'
                              ? 'সুপার অ্যাডমিন'
                              : 'শিক্ষক';
                          Color roleColor = role == 'super_admin'
                              ? Colors.orange
                              : Colors.indigo;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.indigo.withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.indigo.shade50,
                                    backgroundImage:
                                        (photoUrl != null &&
                                            photoUrl.isNotEmpty)
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child:
                                        (photoUrl == null || photoUrl.isEmpty)
                                        ? Text(
                                            name.isNotEmpty ? name[0] : 'U',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  // Expanded ব্যবহারের ফলে রেন্ডারফ্লেক্স বা ওভারফ্লো হবে না
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: roleColor.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                roleDisplayName,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: roleColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // প্রতিষ্ঠানের নাম বড় হলে ওভারফ্লো এড়াতে ellipsis ব্যবহার করা হয়েছে
                                        Text(
                                          widget.academyName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.phone_outlined,
                                              size: 13,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                phone,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // ডানপাশে কল বাটন
                                  IconButton(
                                    onPressed: () =>
                                        _showCallConfirmationDialog(
                                          phone,
                                          name,
                                        ),
                                    icon: const Icon(Icons.phone_rounded),
                                    color: Colors.green,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.green.shade50,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // ব্যাকগ্রাউন্ডে ডাটা লোড হওয়ার সময় হালকা ইনডিকেটর দেখানোর জন্য (ঐচ্ছিক ব্যাকগ্রাউন্ড প্রোগ্রেস)
                if (isLoading && staffList.isNotEmpty)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      color: Colors.indigo,
                    ),
                  ),
                if (isLoading && staffList.isEmpty)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  ),
              ],
            ),
    );
  }
}
