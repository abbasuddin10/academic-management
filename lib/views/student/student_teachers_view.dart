import 'package:academy_management/services/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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

  // ফিল্টার এবং সার্চ সংক্রান্ত ভেরিয়েবল
  String selectedFilter = 'সকল';
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  // ব্যানার অ্যাড সংক্রান্ত ভেরিয়েবল
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  BannerAd? _inListBannerAd1;
  bool _isInListBannerAd1Loaded = false;
  BannerAd? _inListBannerAd2;
  bool _isInListBannerAd2Loaded = false;

  @override
  void initState() {
    super.initState();
    fetchStaffAndAdmins();

    // পেজ ওপেন হওয়ার সাথে সাথে ইন্টারস্টিশিয়াল অ্যাড লোড করা শুরু করা
    AdService.loadInterstitialAd();

    // বটমে ফিক্সড ব্যানার অ্যাড লোড করা[cite: 18]
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      });

    // লিস্টের মাঝে দেখানোর জন্য ১ম ব্যানার অ্যাড লোড করা[cite: 18]
    _inListBannerAd1 = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isInListBannerAd1Loaded = true;
          });
        }
      });

    // লিস্টের মাঝে দেখানোর জন্য ২য় ব্যানার অ্যাড লোড করা[cite: 18]
    _inListBannerAd2 = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() {
            _isInListBannerAd2Loaded = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _inListBannerAd1?.dispose();
    _inListBannerAd2?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ব্যাকগ্রাউন্ডে ডাটা ফেচ করার ফাংশন[cite: 18]
  Future<void> fetchStaffAndAdmins() async {
    try {
      setState(() {
        isLoading = true;
        hasError = false;
      });

      final supabase = Supabase.instance.client;

      // users টেবিল থেকে নির্দিষ্ট একাডেমির শিক্ষক, সুপার অ্যাডমিন এবং স্টাফ ফেচ করা[cite: 18]
      final response = await supabase
          .from('users')
          .select()
          .eq('academy_id', widget.academyId)
          .inFilter('role', ['teacher', 'super_admin', 'staff']);

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

  // কল বাটনে ক্লিক করলে প্রথমে অ্যাড দেখাবে, তারপর পপআপ আসবে
  void _onCallButtonPressed(String phoneNumber, String name) {
    if (phoneNumber.isEmpty || phoneNumber == 'মোবাইল নম্বর নেই') {
      Get.snackbar(
        'দুঃখিত',
        'এই ব্যবহারকারীর কোনো মোবাইল নম্বর যুক্ত করা নেই।',
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
      return;
    }

    // প্রথমে showForcedAd কল হবে, দেখা শেষ হলে পপআপ আসবে
    AdService.showForcedAd(
      onComplete: () {
        _showCallConfirmationDialog(phoneNumber, name);
      },
    );
  }

  // কল করার আগে পপআপ দেখানোর ফাংশন[cite: 18]
  void _showCallConfirmationDialog(String phoneNumber, String name) {
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
        Get.back(); // পপআপ বন্ধ করা[cite: 18]
        _makePhoneCall(phoneNumber);
      },
    );
  }

  // ডায়ালপ্যাডে ফোন নম্বর ওপেন করার ফাংশন[cite: 18]
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
    // ফিল্টার এবং সার্চ অনুযায়ী ডাটা ফিল্টার করা[cite: 18]
    List<Map<String, dynamic>> filteredList = staffList.where((staff) {
      String role = staff['role'] ?? '';
      bool matchesFilter = true;
      if (selectedFilter == 'শিক্ষক') {
        // 'শিক্ষক' ফিল্টারে সুপার অ্যাডমিন এবং শিক্ষক উভয়কেই দেখানো হবে[cite: 18]
        matchesFilter = (role == 'teacher' || role == 'super_admin');
      } else if (selectedFilter == 'স্টাফ') {
        matchesFilter = (role == 'staff');
      }

      String name = (staff['full_name'] ?? '').toLowerCase();
      bool matchesSearch = name.contains(searchQuery.toLowerCase());

      return matchesFilter && matchesSearch;
    }).toList();

    // 'শিক্ষক' ট্যাবের অধীনে সুপার অ্যাডমিনদের যেন সবার উপরে দেখানো হয়, সেজন্য লিস্ট সর্ট করা[cite: 18]
    if (selectedFilter == 'শিক্ষক') {
      filteredList.sort((a, b) {
        String roleA = a['role'] ?? '';
        String roleB = b['role'] ?? '';
        if (roleA == 'super_admin' && roleB != 'super_admin') return -1;
        if (roleA != 'super_admin' && roleB == 'super_admin') return 1;
        return 0;
      });
    }

    // কাউন্ট বের করা[cite: 18]
    int totalCount = staffList.length;
    int teacherCount = staffList
        .where((s) => s['role'] == 'teacher' || s['role'] == 'super_admin')
        .length;
    int staffCount = staffList.where((s) => s['role'] == 'staff').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'শিক্ষক বা স্টাফ খুঁজুন...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : Text(
                'শিক্ষক ও প্রশাসকবৃন্দ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (isSearching) {
                  isSearching = false;
                  searchQuery = '';
                  _searchController.clear();
                } else {
                  isSearching = true;
                }
              });
            },
          ),
        ],
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
                Column(
                  children: [
                    // অ্যাপবারের নিচে ফিল্টার বাটনসমূহ (সংখ্য়া সহ)[cite: 18]
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: Colors.white,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            'সকল',
                            totalCount,
                            selectedFilter == 'সকল',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'শিক্ষক',
                            teacherCount,
                            selectedFilter == 'শিক্ষক',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'স্টাফ',
                            staffCount,
                            selectedFilter == 'স্টাফ',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.grey),
                    Expanded(
                      child: staffList.isEmpty && !isLoading
                          ? const Center(
                              child: Text(
                                'এই মুহূর্তে কোনো শিক্ষক বা অ্যাডমিন সংযুক্ত নেই।',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 15,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredList.length + 2,
                              itemBuilder: (context, index) {
                                // মাঝের কার্ডগুলোর মাঝে ব্যানার অ্যাড সেট করার লজিক[cite: 18]
                                if (index == 2 &&
                                    _isInListBannerAd1Loaded &&
                                    _inListBannerAd1 != null) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    alignment: Alignment.center,
                                    height: _inListBannerAd1!.size.height
                                        .toDouble(),
                                    child: AdWidget(ad: _inListBannerAd1!),
                                  );
                                }
                                if (index == 6 &&
                                    _isInListBannerAd2Loaded &&
                                    _inListBannerAd2 != null) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    alignment: Alignment.center,
                                    height: _inListBannerAd2!.size.height
                                        .toDouble(),
                                    child: AdWidget(ad: _inListBannerAd2!),
                                  );
                                }

                                // আসল লিস্টের ডেটা ইনডেক্স এডজাস্ট করা[cite: 18]
                                int staffIndex = index;
                                if (index > 2 && _isInListBannerAd1Loaded) {
                                  staffIndex--;
                                }
                                if (index > 6 && _isInListBannerAd2Loaded) {
                                  staffIndex--;
                                }

                                if (staffIndex >= filteredList.length) {
                                  return const SizedBox.shrink();
                                }

                                final staff = filteredList[staffIndex];
                                String name = staff['full_name'] ?? 'নামবিহীন';
                                String phone =
                                    staff['phone'] ?? 'মোবাইল নম্বর নেই';
                                String role = staff['role'] ?? '';
                                String? photoUrl = staff['photo_url'];

                                // রোল অনুযায়ী ইউজার টাইপ নির্ধারণ[cite: 18]
                                String roleDisplayName = role == 'super_admin'
                                    ? 'সুপার অ্যাডমিন'
                                    : (role == 'staff' ? 'স্টাফ' : 'শিক্ষক');
                                Color roleColor = role == 'super_admin'
                                    ? Colors.orange
                                    : (role == 'staff'
                                          ? Colors.teal
                                          : Colors.indigo);

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
                                          backgroundColor:
                                              Colors.indigo.shade50,
                                          backgroundImage:
                                              (photoUrl != null &&
                                                  photoUrl.isNotEmpty)
                                              ? NetworkImage(photoUrl)
                                              : null,
                                          child:
                                              (photoUrl == null ||
                                                  photoUrl.isEmpty)
                                              ? Text(
                                                  name.isNotEmpty
                                                      ? name[0]
                                                      : 'U',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.indigo,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 14),
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
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: roleColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      roleDisplayName,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: roleColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
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
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () =>
                                              _onCallButtonPressed(phone, name),
                                          icon: const Icon(Icons.phone_rounded),
                                          color: Colors.green,
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade50,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
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

      // পেজের বোটমে ফিক্সড ব্যানার অ্যাড দেখানোর অংশ[cite: 18]
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : const SizedBox.shrink(),
    );
  }

  // ফিল্টার চিপ বাটন ডিজাইন তৈরির মেথড[cite: 18]
  Widget _buildFilterChip(String title, int count, bool isSelected) {
    return ChoiceChip(
      label: Text('$title ($count)'),
      selected: isSelected,
      selectedColor: Colors.indigo.shade100,
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected ? Colors.indigo.shade900 : Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      onSelected: (bool selected) {
        setState(() {
          selectedFilter = title;
        });
      },
    );
  }
}
