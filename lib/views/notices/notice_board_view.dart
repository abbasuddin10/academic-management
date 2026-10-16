import 'package:academy_management/services/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'create_notice_view.dart'; // 👈 নতুন পেজ ইমপোর্ট করা হয়েছে

class NoticeBoardView extends StatefulWidget {
  final String academyId;
  final String userRole; // 'super_admin', 'teacher', etc.

  const NoticeBoardView({
    super.key,
    required this.academyId,
    required this.userRole,
  });

  @override
  State<NoticeBoardView> createState() => _NoticeBoardViewState();
}

class _NoticeBoardViewState extends State<NoticeBoardView> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> noticesList = [];
  List<String> availableClasses = [];

  BannerAd? _bannerAd; // 👈 ব্যানার অ্যাড ভেরিয়েবল[cite: 2]
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _initBannerAd(); // 👈 ব্যানার অ্যাড ইনিশিয়ালাইজ[cite: 2]
    _fetchNotices();
    if (widget.userRole == 'super_admin') {
      _fetchClasses();
    }
  }

  // 👈 ব্যানার অ্যাড সেটআপ ফাংশন[cite: 2]
  void _initBannerAd() {
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _bannerAd?.dispose(); // 👈 ব্যানার অ্যাড ডিসপোজ
    super.dispose();
  }

  Future<void> _fetchClasses() async {
    try {
      final res = await supabase
          .from('students')
          .select('class')
          .eq('academy_id', widget.academyId);

      Set<String> classes = {};
      for (var item in (res as List)) {
        String? cls = item['class']?.toString().trim();
        if (cls != null && cls.isNotEmpty) {
          classes.add(cls);
        }
      }
      setState(() {
        availableClasses = classes.toList();
      });
    } catch (e) {
      print("Error fetching classes: $e");
    }
  }

  Future<void> _fetchNotices() async {
    try {
      setState(() => isLoading = true);
      var query = supabase
          .from('notices')
          .select()
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      final response = await query;
      setState(() {
        noticesList = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar(
        "ত্রুটি",
        "নোটিশ লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // 👈 সুপাবেস থেকে নোটিশ ডিলিট করার ফাংশন
  Future<void> _deleteNotice(String noticeId) async {
    bool? confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('নোটিশ মুছুন'),
        content: const Text('আপনি কি নিশ্চিত যে এই নোটিশটি মুছে ফেলতে চান?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text(
              'মুছে ফেলুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('notices').delete().eq('id', noticeId);
        _fetchNotices(); // রিয়েল-টাইম আপডেট
        Get.snackbar(
          "সফল",
          "নোটিশটি মুছে ফেলা হয়েছে!",
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } catch (e) {
        Get.snackbar(
          "ত্রুটি",
          "মুছে ফেলতে সমস্যা হয়েছে: $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  // 👈 সুপাবেসে নোটিশ এডিট করার ডায়ালগ ও ফাংশন
  void _editNoticeDialog(Map<String, dynamic> notice) {
    final titleEditController = TextEditingController(
      text: notice['title'] ?? '',
    );
    final descEditController = TextEditingController(
      text: notice['description'] ?? '',
    );

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('নোটিশ এডিট করুন'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleEditController,
                decoration: const InputDecoration(
                  labelText: 'শিরোনাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descEditController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'বিবরণ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              if (titleEditController.text.trim().isEmpty ||
                  descEditController.text.trim().isEmpty) {
                Get.snackbar("সতর্কতা", "শিরোনাম ও বিবরণ দিন!");
                return;
              }
              Get.back();
              try {
                await supabase
                    .from('notices')
                    .update({
                      'title': titleEditController.text.trim(),
                      'description': descEditController.text.trim(),
                    })
                    .eq('id', notice['id']);

                _fetchNotices(); // রিয়েল-টাইম আপডেট
                Get.snackbar(
                  "সফল",
                  "নোটিশ সফলভাবে আপডেট করা হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  "ত্রুটি",
                  "আপডেট করতে সমস্যা হয়েছে: $e",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text(
              'আপডেট করুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 👈 পপ-আপ ডায়ালগে সম্পূর্ণ নোটিশ দেখানোর হেল্পার
  void _showNoticeDetailsDialog(
    Map<String, dynamic> notice,
    String targetText,
    String? fileUrl,
  ) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          notice['title'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notice['description'] ?? '',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              if (fileUrl != null && fileUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                  onPressed: () async {
                    final Uri uri = Uri.parse(fileUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('সংযুক্ত ফাইল/ডকুমেন্ট দেখুন'),
                ),
              ],
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    targetText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    notice['created_at'] != null
                        ? notice['created_at'].toString().substring(0, 10)
                        : '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('বন্ধ করুন'),
          ),
        ],
      ),
    );
  }

  // 👈 নতুন পেজ ওপেন করার ফাংশন
  Future<void> _navigateToCreateNotice() async {
    if (widget.userRole != 'super_admin') {
      Get.snackbar(
        "অপারেশন নিষেধ",
        "শুধুমাত্র অ্যাডমিন নোটিশ প্রকাশ করতে পারবেন!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final result = await Get.to(
      () => CreateNoticeView(
        academyId: widget.academyId,
        userRole: widget.userRole,
        availableClasses: availableClasses,
      ),
    );

    // যদি নোটিশ সফলভাবে তৈরি হয়, তবে নোটিশ বোর্ড রিফ্রেশ হবে
    if (result == true) {
      _fetchNotices();
    }
  }

  // 👈 প্রতি ৪টি কার্ড পর পর ব্যানার অ্যাড দেখানোর হেল্পার উইজেট[cite: 2]
  Widget _buildBannerAdItem() {
    final BannerAd bannerAd = AdService.createBannerAd()..load();
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = (widget.userRole == 'super_admin');

    return Scaffold(
      appBar: AppBar(
        title: const Text('নোটিশ বোর্ড'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              onPressed: _navigateToCreateNotice, // 👈 আলাদা পেজে নিয়ে যাবে
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'নোটিশ দিন',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.teal),
                  )
                : noticesList.isEmpty
                ? const Center(
                    child: Text(
                      'এই মুহূর্তে কোনো নোটিশ নেই।',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchNotices,
                    child: ListView.builder(
                      itemCount:
                          noticesList.length +
                          (noticesList.isNotEmpty
                              ? (noticesList.length ~/ 4)
                              : 0),
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        // 👈 প্রতি ৪টি কার্ড পর পর ব্যানার অ্যাড রেন্ডার করার হিসাব
                        int realIndex = index;
                        for (int i = 0; i <= index; i++) {
                          if (i > 0 && (i + 1) % 5 == 0) {
                            if (index == i) {
                              return _buildBannerAdItem();
                            }
                            realIndex--;
                          }
                        }

                        if (realIndex >= noticesList.length) {
                          return const SizedBox.shrink();
                        }

                        final notice = noticesList[realIndex];
                        String targetText = '';
                        String tType = notice['target_type'] ?? '';
                        if (tType == 'all_students') {
                          targetText = 'প্রাপক: সকল ছাত্র-ছাত্রী';
                        } else if (tType == 'class') {
                          targetText =
                              'প্রাপক ক্লাস: ${notice['target_class']}';
                        } else if (tType == 'teachers') {
                          targetText = 'প্রাপক: সকল শিক্ষক';
                        } else {
                          targetText = 'প্রাপক: সকলের জন্য';
                        }

                        String? fileUrl = notice['file_url'];

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showNoticeDetailsDialog(
                              notice,
                              targetText,
                              fileUrl,
                            ), // 👈 কার্ডে ক্লিক করলে পপ-আপ আসবে
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.campaign,
                                        color: Colors.teal,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notice['title'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      // 👈 অ্যাডমিনের জন্য এডিট ও ডিলিট বাটন
                                      if (isAdmin) ...[
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _editNoticeDialog(notice),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          onPressed: () => _deleteNotice(
                                            notice['id'].toString(),
                                          ),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // 👈 বিবরণ সর্বোচ্চ ৩ লাইনে সীমাবদ্ধ রাখা হয়েছে
                                  Text(
                                    notice['description'] ?? '',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),

                                  // ফাইল বা ইমেজ থাকলে ব্রাউজার বা অ্যাপে খোলার বাটন
                                  if (fileUrl != null &&
                                      fileUrl.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.teal,
                                        side: const BorderSide(
                                          color: Colors.teal,
                                        ),
                                      ),
                                      onPressed: () async {
                                        final Uri uri = Uri.parse(fileUrl);
                                        try {
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(
                                              uri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          } else {
                                            Get.snackbar(
                                              "ত্রুটি",
                                              "ফাইলটি ওপেন করা সম্ভব হচ্ছে না!",
                                              backgroundColor: Colors.red,
                                              colorText: Colors.white,
                                            );
                                          }
                                        } catch (e) {
                                          Get.snackbar(
                                            "ত্রুটি",
                                            "সমস্যা হয়েছে: $e",
                                            backgroundColor: Colors.red,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'সংযুক্ত ফাইল/ডকুমেন্ট দেখুন',
                                      ),
                                    ),
                                  ],

                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          targetText,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.teal.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        notice['created_at'] != null
                                            ? notice['created_at']
                                                  .toString()
                                                  .substring(0, 10)
                                            : '',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          // 👈 স্ক্রিনের নিচে ফিক্সড ব্যানার অ্যাড উইজেট[cite: 2]
          if (_isBannerAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
