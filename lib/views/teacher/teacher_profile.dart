import 'package:academy_management/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class TeacherProfileView extends StatefulWidget {
  final String teacherId;
  final String academyId;

  const TeacherProfileView({
    super.key,
    required this.teacherId,
    required this.academyId,
  });

  @override
  State<TeacherProfileView> createState() => _TeacherProfileViewState();
}

class _TeacherProfileViewState extends State<TeacherProfileView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isUpdating = false;
  Map<String, dynamic>? _teacherData;
  String _academyName = 'একাডেমি নাম লোড হচ্ছে...';
  List<Map<String, dynamic>> _attendanceHistory = [];

  // হাজিরা কাউন্ট
  int _presentOnTimeDays = 0;
  int _lateDays = 0;
  double _onTimePercentage = 0.0;

  // রানিং মাসের কাউন্ট
  int _currentMonthTotal = 0;
  int _currentMonthOnTime = 0;
  int _currentMonthLate = 0;
  double _currentMonthPercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchDataByIDs();
  }

  // ব্যাকগ্রাউন্ডে ডেটা লোড করার জন্য
  Future<void> _fetchDataByIDs({bool background = false}) async {
    if (!mounted) return;
    if (!background && _teacherData == null) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      Map<String, dynamic>? userResponse;

      if (widget.teacherId.isNotEmpty &&
          widget.teacherId != 'null' &&
          widget.academyId.isNotEmpty &&
          widget.academyId != 'null') {
        userResponse = await supabase
            .from('users')
            .select()
            .eq('id', widget.teacherId.trim())
            .eq('academy_id', widget.academyId.trim())
            .maybeSingle();
      }

      if (userResponse == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      String actualTeacherId = userResponse['id']?.toString() ?? '';
      String actualAcademyId =
          userResponse['academy_id']?.toString() ?? widget.academyId;

      // academies টেবিল থেকে 'academy_name' আনা
      if (actualAcademyId.isNotEmpty) {
        final academyResponse = await supabase
            .from('academies')
            .select('academy_name')
            .eq('id', actualAcademyId.trim())
            .maybeSingle();

        if (academyResponse != null) {
          _academyName =
              academyResponse['academy_name'] ?? 'প্রাতিষ্ঠানিক নাম নেই';
        }
      }

      // হাজিরা হিস্টোরি আনা
      List<Map<String, dynamic>> fetchedAttendance = [];
      if (actualTeacherId.isNotEmpty && actualAcademyId.isNotEmpty) {
        final attendanceResponse = await supabase
            .from('teacher_attendance')
            .select()
            .eq('academy_id', actualAcademyId.trim())
            .eq('teacher_id', actualTeacherId.trim())
            .order('date', ascending: false);

        fetchedAttendance = List<Map<String, dynamic>>.from(
          attendanceResponse,
        );
            }

      int total = fetchedAttendance.length;
      int onTimeCount = 0;
      int lateCount = 0;

      String currentYearMonth = DateTime.now().toIso8601String().substring(
        0,
        7,
      );
      int cmTotal = 0;
      int cmOnTime = 0;
      int cmLate = 0;

      for (var item in fetchedAttendance) {
        String status = item['status']?.toString() ?? 'Present';
        bool isLate = status.toLowerCase() == 'late';

        if (isLate) {
          lateCount++;
        } else {
          onTimeCount++;
        }

        String dateStr =
            item['date']?.toString() ?? item['created_at']?.toString() ?? '';
        if (dateStr.startsWith(currentYearMonth)) {
          cmTotal++;
          if (isLate) {
            cmLate++;
          } else {
            cmOnTime++;
          }
        }
      }

      double percentage = total > 0 ? (onTimeCount / total) * 100 : 0.0;
      double cmPercentage = cmTotal > 0 ? (cmOnTime / cmTotal) * 100 : 0.0;

      if (mounted) {
        setState(() {
          _teacherData = userResponse;
          _attendanceHistory = fetchedAttendance;

          _presentOnTimeDays = onTimeCount;
          _lateDays = lateCount;
          _onTimePercentage = percentage;

          _currentMonthTotal = cmTotal;
          _currentMonthOnTime = cmOnTime;
          _currentMonthLate = cmLate;
          _currentMonthPercentage = cmPercentage;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile data by IDs: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // প্রোফাইল এডিট করার ডায়ালগ বক্স
  void _showEditProfileDialog() {
    final phoneController = TextEditingController(
      text: _teacherData?['phone'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'প্রোফাইল তথ্য আপডেট করুন',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'নতুন মোবাইল নম্বর',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (pickedFile != null) {
                        await _uploadImageAndVerify(
                          File(pickedFile.path),
                          phoneController.text.trim(),
                        );
                      }
                    },
                    icon: Icon(Icons.photo_library),
                    label: Text('গ্যালারি থেকে ছবি পরিবর্তন করুন'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.tileOf(context, Colors.teal),
                      foregroundColor: AppTheme.tileInkOf(context, Colors.teal),
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('বাতিল', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.tileInkOf(context, Colors.teal),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _updateProfileInSupabase(
                  newPhone: phoneController.text.trim(),
                  newPhotoUrl: _teacherData?['photo_url'],
                );
              },
              child: const Text('সংরক্ষণ করুন'),
            ),
          ],
        );
      },
    );
  }

  // Supabase-এ প্রোফাইল আপডেট করার মেথড
  Future<void> _updateProfileInSupabase({
    required String newPhone,
    String? newPhotoUrl,
  }) async {
    setState(() => _isUpdating = true);
    try {
      final updateData = <String, dynamic>{};
      if (newPhone.isNotEmpty) updateData['phone'] = newPhone;
      if (newPhotoUrl != null) updateData['photo_url'] = newPhotoUrl;

      if (updateData.isNotEmpty) {
        await supabase
            .from('users')
            .update(updateData)
            .eq('id', widget.teacherId.trim())
            .eq('academy_id', widget.academyId.trim());

        await _fetchDataByIDs(background: true);
        if (!mounted) return;

        Get.snackbar(
          'সফল হয়েছে',
          'প্রোফাইল সফলভাবে আপডেট করা হয়েছে!',
          backgroundColor: AppTheme.tileInkOf(context, Colors.teal),
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
        );
      }
    } catch (e) {
      debugPrint("Error updating profile: $e");
      Get.snackbar(
        'ত্রুটি',
        'আপডেট করতে সমস্যা হয়েছে!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // গ্যালারি থেকে ছবি নিয়ে 'teacher_photos' বাক্যাটে আপলোড করা
  Future<void> _uploadImageAndVerify(File imageFile, String phone) async {
    setState(() => _isUpdating = true);
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('teacher_photos').upload(fileName, imageFile);
      final imageUrl = supabase.storage
          .from('teacher_photos')
          .getPublicUrl(fileName);

      await _updateProfileInSupabase(newPhone: phone, newPhotoUrl: imageUrl);
    } catch (e) {
      debugPrint("Storage upload error: $e");
      setState(() => _isUpdating = false);
      Get.snackbar(
        'ত্রুটি',
        'ছবি আপলোড করতে ব্যর্থ হয়েছে!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'শিক্ষক প্রোফাইল ও প্রগ্রেস',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.teal),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _teacherData == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'কোনো প্রফাইল তথ্য পাওয়া যায়নি!',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _fetchDataByIDs(background: false),
                    child: const Text('পুনরায় চেষ্টা করুন'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _fetchDataByIDs(background: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ১. প্রোফাইল হেডার কার্ড (এডিট আইকন একদম নিচে ডানে সুরক্ষিতভাবে সেট করা)
                        Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                45,
                                16,
                              ), // ডানপাশে আইকনের জন্য জায়গা রাখা হয়েছে
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceOf(context),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      final picker = ImagePicker();
                                      final pickedFile = await picker.pickImage(
                                        source: ImageSource.gallery,
                                      );
                                      if (pickedFile != null) {
                                        await _uploadImageAndVerify(
                                          File(pickedFile.path),
                                          _teacherData!['phone'] ?? '',
                                        );
                                      }
                                    },
                                    child: Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 35,
                                          backgroundColor: AppTheme.tileOf(context, Colors.teal),
                                          backgroundImage:
                                              (_teacherData!['photo_url'] !=
                                                      null &&
                                                  _teacherData!['photo_url']
                                                      .toString()
                                                      .isNotEmpty)
                                              ? NetworkImage(
                                                  _teacherData!['photo_url'],
                                                )
                                              : null,
                                          child:
                                              (_teacherData!['photo_url'] ==
                                                      null ||
                                                  _teacherData!['photo_url']
                                                      .toString()
                                                      .isEmpty)
                                              ? Icon(
                                                  Icons.person,
                                                  size: 35,
                                                  color: Colors.teal.shade700,
                                                )
                                              : null,
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.tileInkOf(context, Colors.teal),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _teacherData!['full_name'] ??
                                              'নামবিহীন শিক্ষক',
                                          maxLines:
                                              1, // নাম এক লাইনে সীমাবদ্ধ রাখবে
                                          overflow: TextOverflow
                                              .ellipsis, // নাম অনেক বড় হলে শেষে ডট ডট (...) দেখাবে
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _academyName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.teal.shade700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          _teacherData!['email'] ?? 'ইমেইল নেই',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.mutedOf(context),
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.phone_android,
                                              size: 13,
                                              color: AppTheme.tileInkOf(context, Colors.teal),
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              _teacherData!['phone'] ??
                                                  'নম্বর দেওয়া নেই',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.tileInkOf(context, Colors.teal),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // এডিট আইকন একদম নিচে ডানে পজিশন করা হয়েছে
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: InkWell(
                                onTap: _showEditProfileDialog,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.tileOf(context, Colors.teal),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: AppTheme.tileInkOf(context, Colors.teal),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ২. রানিং মাস ও সামগ্রিক প্রোগ্রেস গ্রিড
                        Row(
                          children: [
                            Expanded(
                              child: _buildProgressCard(
                                title: 'চলতি মাস',
                                percentage: _currentMonthPercentage,
                                onTime: _currentMonthOnTime,
                                late: _currentMonthLate,
                                total: _currentMonthTotal,
                                isPrimary: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildProgressCard(
                                title: 'সর্বমোট',
                                percentage: _onTimePercentage,
                                onTime: _presentOnTimeDays,
                                late: _lateDays,
                                total: _presentOnTimeDays + _lateDays,
                                isPrimary: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ৩. সাম্প্রতিক হাজিরা হিস্টোরি
                        Text(
                          'সাম্প্রতিক হাজিরা হিস্টোরি',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        SizedBox(height: 10),
                        _attendanceHistory.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceOf(context),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'কোনো হাজিরা রেকর্ড পাওয়া যায়নি।',
                                    style: TextStyle(
                                      color: AppTheme.mutedOf(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _attendanceHistory.length > 10
                                    ? 10
                                    : _attendanceHistory.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = _attendanceHistory[index];
                                  String dateStr =
                                      item['date']?.toString() ??
                                      item['created_at']?.toString() ??
                                      '';
                                  if (dateStr.isNotEmpty &&
                                      dateStr.length >= 10) {
                                    dateStr = dateStr.substring(0, 10);
                                  }
                                  String status =
                                      item['status']?.toString() ?? 'Present';
                                  bool isLate =
                                      (status.toLowerCase() == 'late');

                                  return Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceOf(context),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.02),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color:
                                                (isLate
                                                        ? Colors.amber
                                                        : Colors.green)
                                                    .withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isLate
                                                ? Icons.access_time_filled
                                                : Icons.check_circle,
                                            color: isLate
                                                ? AppTheme.tileInkOf(context, Colors.amber)
                                                : Colors.green.shade700,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isLate
                                                    ? 'বিলম্বে উপস্থিত (Late)'
                                                    : 'সময়মতো উপস্থিত',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: isLate
                                                      ? AppTheme.tileInkOf(context, Colors.amber)
                                                      : AppTheme.inkOf(context),
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                dateStr,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.mutedOf(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isLate
                                                ? AppTheme.tileOf(context, Colors.amber)
                                                : AppTheme.tileOf(context, Colors.teal),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            isLate ? 'লেট' : 'উপস্থিত',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isLate
                                                  ? AppTheme.tileInkOf(context, Colors.amber)
                                                  : AppTheme.tileInkOf(context, Colors.teal),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
                if (_isUpdating)
                  Container(
                    color: Colors.black.withValues(alpha: 0.2),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildProgressCard({
    required String title,
    required double percentage,
    required int onTime,
    required int late,
    required int total,
    required bool isPrimary,
  }) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPrimary ? AppTheme.tileInkOf(context, Colors.teal) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isPrimary ? Colors.white : AppTheme.tileInkOf(context, Colors.teal),
            ),
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: isPrimary
                ? AppTheme.tileInkOf(context, Colors.teal)
                : AppTheme.altSurfaceOf(context),
            color: percentage >= 75 ? Colors.greenAccent : Colors.amberAccent,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            'সময়মতো: $onTime | লেট: $late',
            style: TextStyle(
              fontSize: 10,
              color: isPrimary ? Colors.white60 : Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
