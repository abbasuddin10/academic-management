import 'package:academy_management/views/dashboard/AcademyQRCodeView.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';

class AttendancePageView extends StatefulWidget {
  final String academyId;
  final String userRole;

  const AttendancePageView({
    super.key,
    required this.academyId,
    required this.userRole,
  });

  @override
  State<AttendancePageView> createState() => _AttendancePageViewState();
}

class _AttendancePageViewState extends State<AttendancePageView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isListLoading = false;
  String? _savedLocation;
  String _securityHashToken = '';
  double? _savedLatitude;
  double? _savedLongitude;
  int _allowedRadius = 100;
  String _startTime = '09:00:00';

  List<Map<String, dynamic>> _usersList = [];
  Map<String, Map<String, dynamic>> _todayAttendanceMap = {};
  Map<String, List<Map<String, dynamic>>> _pastDaysAttendanceMap = {};
  List<String> _pastDatesList = [];
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _fetchAcademyDataAndUsers();
  }

  Future<void> _fetchAcademyDataAndUsers({bool isBackground = false}) async {
    try {
      if (!isBackground) {
        if (mounted) setState(() => _isLoading = true);
      } else {
        if (mounted) setState(() => _isListLoading = true);
      }

      final academyRes = await supabase
          .from('academies')
          .select(
            'location, security_token, latitude, longitude, allowed_radius, start_time',
          )
          .eq('id', widget.academyId)
          .maybeSingle();

      if (academyRes != null) {
        _savedLocation = academyRes['location']?.toString();
        _securityHashToken =
            academyRes['security_token']?.toString() ?? _generateSecureToken();

        if (academyRes['latitude'] != null) {
          _savedLatitude = double.tryParse(academyRes['latitude'].toString());
        }
        if (academyRes['longitude'] != null) {
          _savedLongitude = double.tryParse(academyRes['longitude'].toString());
        }

        if (academyRes['allowed_radius'] != null) {
          _allowedRadius =
              int.tryParse(academyRes['allowed_radius'].toString()) ?? 100;
        }
        _startTime = academyRes['start_time']?.toString() ?? '09:00:00';
      }

      final usersRes = await supabase
          .from('users')
          .select('id, full_name, phone, photo_url')
          .eq('academy_id', widget.academyId);

      _usersList = List<Map<String, dynamic>>.from(usersRes);

      DateTime now = DateTime.now();
      String todayDate = DateFormat('yyyy-MM-dd').format(now);
      // সঠিক UTC টাইম তৈরি করে ডাটাবেসে পাঠানোর জন্য
      String checkInTimeStr = DateTime.now().toUtc().toIso8601String();

      _pastDatesList = [];
      for (int i = 1; i <= 3; i++) {
        DateTime pastDate = now.subtract(Duration(days: i));
        _pastDatesList.add(DateFormat('yyyy-MM-dd').format(pastDate));
      }

      String oldestDate = _pastDatesList.last;
      final attendanceRes = await supabase
          .from('teacher_attendance')
          .select(
            'teacher_id, check_in_time, status, date, teacher_name, latitude, longitude',
          )
          .eq('academy_id', widget.academyId)
          .gte('date', oldestDate);

      _todayAttendanceMap.clear();
      _pastDaysAttendanceMap.clear();
      for (String dateStr in _pastDatesList) {
        _pastDaysAttendanceMap[dateStr] = [];
      }

      for (var att in attendanceRes) {
        String attDate = att['date']?.toString() ?? '';
        String userId = att['teacher_id']?.toString().trim() ?? '';

        if (attDate == todayDate) {
          _todayAttendanceMap[userId] = att;
        } else if (_pastDaysAttendanceMap.containsKey(attDate)) {
          _pastDaysAttendanceMap[attDate]!.add(att);
        }
      }
    } catch (e) {
      print("Error fetching data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isListLoading = false;
        });
      }
    }
  }

  String _generateSecureToken() {
    var bytes = utf8.encode(
      '${widget.academyId}_${DateTime.now().toIso8601String()}',
    );
    return sha256.convert(bytes).toString().substring(0, 16);
  }

  void _showSetLocationDialog() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar(
        "লোকেশন বন্ধ",
        "দয়া করে জিপিএস অন করুন",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Colors.teal)),
      barrierDismissible: false,
    );

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (position.isMocked) {
        Get.back();
        Get.snackbar(
          "সতর্কতা",
          "ফেক জিপিএস ব্যবহার নিষেধ!",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
      Get.back();

      final TextEditingController locationController = TextEditingController(
        text: _savedLocation ?? '',
      );
      final TextEditingController radiusController = TextEditingController(
        text: _allowedRadius.toString(),
      );
      final TextEditingController timeController = TextEditingController(
        text: _startTime,
      );

      bool updateLocationPin = false;

      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: const [
                    Icon(Icons.settings_suggest, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      'জিও-ফেন্স ও শিডিউল সেটিংস',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'প্রতিষ্ঠানের সঠিক তথ্য এবং সময় আপডেট করুন।',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'প্রতিষ্ঠানের নাম/ঠিকানা',
                          prefixIcon: Icon(Icons.business, color: Colors.teal),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: radiusController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'রেডিয়াস (মিটারে)',
                          prefixIcon: Icon(Icons.radar, color: Colors.teal),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: timeController,
                        decoration: const InputDecoration(
                          labelText: 'ইন-টাইম (যেমন: 09:00:00)',
                          prefixIcon: Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: CheckboxListTile(
                          title: const Text(
                            'নতুন কিউআর কোড জেনারেট করুন',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: const Text(
                            'শুধুমাত্র লোকেশন পরিবর্তন বা সিকিউরিটি রিসেট করার প্রয়োজন হলে টিক দিন।',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          value: updateLocationPin,
                          onChanged: (val) {
                            setDialogState(() {
                              updateLocationPin = val ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'বাতিল',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      String newLocation = locationController.text.trim();
                      int newRadius =
                          int.tryParse(radiusController.text.trim()) ?? 100;
                      String newTime = timeController.text.trim();
                      if (newLocation.isEmpty) return;

                      String newToken =
                          (_savedLatitude == null || updateLocationPin)
                          ? _generateSecureToken()
                          : _securityHashToken;

                      Navigator.pop(context);
                      if (mounted) setState(() => _isLoading = true);

                      await supabase
                          .from('academies')
                          .update({
                            'location': newLocation,
                            'security_token': newToken,
                            'latitude': position.latitude,
                            'longitude': position.longitude,
                            'allowed_radius': newRadius,
                            'start_time': newTime,
                          })
                          .eq('id', widget.academyId);

                      if (mounted) {
                        setState(() {
                          _savedLocation = newLocation;
                          _securityHashToken = newToken;
                          _savedLatitude = position.latitude;
                          _savedLongitude = position.longitude;
                          _allowedRadius = newRadius;
                          _startTime = newTime;
                        });
                      }

                      Get.snackbar(
                        "সফল",
                        updateLocationPin
                            ? "লোকেশন, শিডিউল এবং নতুন কিউআর কোড সফলভাবে আপডেট হয়েছে!"
                            : "ইন-টাইম ও শিডিউল সফলভাবে আপডেট হয়েছে!",
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                      );
                    },
                    child: const Text('সংরক্ষণ করুন'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
    }
  }

  void _openScanner() {
    if (_savedLocation == null ||
        _savedLatitude == null ||
        _savedLongitude == null) {
      Get.snackbar(
        "সতর্কতা",
        "প্রথমে অ্যাডমিন দ্বারা জিও-ফেন্স লোকেশন সেট করতে হবে!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    Get.to(
      () => Scaffold(
        appBar: AppBar(
          title: const Text('হাজিরা কিউআর স্ক্যান করুন'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: MobileScanner(
          onDetect: (capture) async {
            if (_isProcessingScan) return;
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final String? code = barcode.rawValue;
              if (code != null) {
                _isProcessingScan = true;
                Get.back();
                await _verifyAttendanceProcess(code);
                _isProcessingScan = false;
                break;
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _verifyAttendanceProcess(String scannedData) async {
    if (!scannedData.contains(widget.academyId) ||
        !scannedData.contains(_securityHashToken)) {
      Get.snackbar(
        "ভুল কোড",
        "এটি এই প্রতিষ্ঠানের বৈধ কিউআর কোড নয়!",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    DateTime now = DateTime.now();
    String todayDate = DateFormat('yyyy-MM-dd').format(now);

    List<String> timeParts = _startTime.split(':');
    DateTime startTimeToday = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
      int.parse(timeParts.length > 2 ? timeParts[2] : '0'),
    );

    DateTime attendanceDeadline = startTimeToday.add(const Duration(hours: 10));

    if (now.isAfter(attendanceDeadline)) {
      Get.snackbar(
        "সময় শেষ",
        "আজকের হাজিরা নেওয়ার সময় পার হয়ে গেছে! নির্দিষ্ট ১০ ঘণ্টার টাইম উইন্ডো শেষ।",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar(
        "লোকেশন বন্ধ",
        "দয়া করে জিপিএস অন করুন",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Colors.teal)),
      barrierDismissible: false,
    );

    try {
      Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (currentPosition.isMocked) {
        Get.back();
        Get.snackbar(
          "নিরাপত্তা সতর্কতা",
          "ফেক জিপিএস ব্যবহার করা নিষিদ্ধ!",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      double distanceInMeters = Geolocator.distanceBetween(
        _savedLatitude!,
        _savedLongitude!,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      Get.back();

      if (distanceInMeters <= _allowedRadius) {
        final authUser = supabase.auth.currentUser;
        if (authUser == null) {
          Get.snackbar(
            "ত্রুটি",
            "লগইন করা ইউজার পাওয়া যায়নি!",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        final userRecord = await supabase
            .from('users')
            .select('id, full_name')
            .eq('email', authUser.email ?? '')
            .eq('academy_id', widget.academyId)
            .maybeSingle();

        if (userRecord == null) {
          Get.snackbar(
            "ত্রুটি",
            "ইউজার টেবিল থেকে আপনার তথ্য পাওয়া যায়নি!",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        String currentUserId = userRecord['id'].toString().trim();
        String currentUserName =
            userRecord['full_name']?.toString() ?? 'শিক্ষক';

        if (currentUserId.isEmpty) {
          Get.snackbar(
            "ত্রুটি",
            "ইউনিক আইডি পাওয়া যায়নি!",
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        if (_todayAttendanceMap.containsKey(currentUserId)) {
          Get.snackbar(
            "আজকে নেওয়া হয়ে গেছে",
            "আপনার হাজিরা আজকে ইতিমধ্যে সফলভাবে নেওয়া হয়েছে!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        final existingCheck = await supabase
            .from('teacher_attendance')
            .select('id')
            .eq('academy_id', widget.academyId)
            .eq('teacher_id', currentUserId)
            .eq('date', todayDate)
            .maybeSingle();

        if (existingCheck != null) {
          setState(() {
            _todayAttendanceMap[currentUserId] = {'status': 'Present'};
          });
          Get.snackbar(
            "আজকে নেওয়া হয়ে গেছে",
            "আপনার হাজিরা আজকে ইতিমধ্যে সফলভাবে নেওয়া হয়েছে!",
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          return;
        }

        String attendanceStatus = now.isAfter(startTimeToday)
            ? 'Late'
            : 'Present';

        // সঠিক UTC টাইম সেভ করার কোড (কোনো অতিরিক্ত ঘণ্টা যোগ করা হয়নি)
        String checkInTimeStr = DateTime.now().toUtc().toIso8601String();

        try {
          await supabase.from('teacher_attendance').insert({
            'academy_id': widget.academyId,
            'teacher_id': currentUserId,
            'teacher_name': currentUserName,
            'date': todayDate,
            'status': attendanceStatus,
            'distance_meters': distanceInMeters,
            'check_in_time': checkInTimeStr,
            'latitude': currentPosition.latitude,
            'longitude': currentPosition.longitude,
          });
        } catch (insertError) {
          print("Insert Error Detail: $insertError");
        }

        if (mounted) {
          setState(() {
            _todayAttendanceMap[currentUserId] = {
              'teacher_id': currentUserId,
              'teacher_name': currentUserName,
              'date': todayDate,
              'status': attendanceStatus,
              'check_in_time': checkInTimeStr,
              'latitude': currentPosition.latitude,
              'longitude': currentPosition.longitude,
            };
          });
        }

        Get.snackbar(
          "সফল",
          attendanceStatus == 'Late'
              ? "হাজিরা রেকর্ড হয়েছে (বিলম্বিত বা Late)!"
              : "হাজিরা সফলভাবে রেকর্ড করা হয়েছে (Present)!",
          backgroundColor: attendanceStatus == 'Late'
              ? Colors.amber.shade800
              : Colors.green,
          colorText: Colors.white,
        );

        if (mounted) {
          await _fetchAcademyDataAndUsers(isBackground: true);
        }
      } else {
        Get.snackbar(
          "ব্যর্থ",
          "আপনি প্রতিষ্ঠানের সীমার বাইরে আছেন! (${distanceInMeters.toStringAsFixed(0)} মিটার দূরে)",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        "ত্রুটি",
        "লোকেশন যাচাই করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = (widget.userRole == 'super_admin');

    return Scaffold(
      appBar: AppBar(
        title: const Text('এটেন্ডেন্স ম্যানেজমেন্ট'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: isAdmin
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: "btn1",
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AcademyQRCodeView(
                        academyId: widget.academyId,
                        securityToken: _securityHashToken,
                        academyName: _savedLocation ?? 'প্রতিষ্ঠান',
                      ),
                    );
                  },
                  backgroundColor: Colors.indigo,
                  icon: const Icon(Icons.qr_code, color: Colors.white),
                  label: const Text(
                    'কিউআর কোড দেখুন',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: "btn2",
                  onPressed: _showSetLocationDialog,
                  backgroundColor: Colors.teal,
                  icon: const Icon(Icons.location_on, color: Colors.white),
                  label: const Text(
                    'জিও-ফেন্স সেট করুন',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : RefreshIndicator(
              onRefresh: () => _fetchAcademyDataAndUsers(isBackground: true),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.qr_code_scanner,
                          size: 40,
                          color: Colors.teal,
                        ),

                        const SizedBox(height: 4),
                        Text(
                          _savedLocation != null
                              ? 'লোকেশন: $_savedLocation\nসীমাবদ্ধতা: $_allowedRadius মিটার | ইন-টাইম: $_startTime'
                              : '⚠️ কোনো জিও-ফেন্স লোকেশন সেট করা হয়নি!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: _savedLocation != null
                                ? Colors.black87
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('হাজিরা নিতে স্ক্যান করুন'),
                          onPressed: _openScanner,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'আজকের উপস্থিতি তালিকা (রিয়েল-টাইম)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (_isListLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.teal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _usersList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('কোনো ব্যবহারকারী পাওয়া যায়নি'),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _usersList.length,
                          itemBuilder: (context, index) {
                            final user = _usersList[index];
                            final userId = user['id']?.toString().trim() ?? '';
                            final userName =
                                user['full_name'] ?? 'নামবিহীন ইউজার';
                            final userPhone = user['phone'] ?? 'নম্বর নেই';
                            final photoUrl = user['photo_url'];

                            final attendance = _todayAttendanceMap[userId];
                            bool isPresent = attendance != null;
                            String status = attendance?['status'] ?? 'Absent';
                            String timeStr = '';

                            if (isPresent &&
                                attendance['check_in_time'] != null) {
                              DateTime parsedTime = DateTime.parse(
                                attendance['check_in_time'],
                              );
                              // সঠিক বাংলাদেশ সময় দেখানোর জন্য
                              DateTime bdTime = parsedTime.isUtc
                                  ? parsedTime.add(const Duration(hours: 6))
                                  : parsedTime;
                              timeStr = DateFormat('hh:mm a').format(bdTime);
                            }

                            Color statusColor = status == 'Late'
                                ? Colors.amber.shade800
                                : (isPresent ? Colors.green : Colors.red);

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage:
                                      (photoUrl != null &&
                                          photoUrl.toString().isNotEmpty)
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child:
                                      (photoUrl == null ||
                                          photoUrl.toString().isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      userPhone,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (isPresent) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'সময়: $timeStr ($status)',
                                        style: TextStyle(
                                          color: status == 'Late'
                                              ? Colors.amber.shade800
                                              : Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Icon(
                                  isPresent ? Icons.check_circle : Icons.cancel,
                                  color: statusColor,
                                  size: 28,
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 25),
                  const Divider(thickness: 2),
                  const SizedBox(height: 10),
                  const Text(
                    'গত ৩ দিনের স্কান রেজাল্ট',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._pastDatesList.map((dateStr) {
                    List<Map<String, dynamic>> dayRecords =
                        _pastDaysAttendanceMap[dateStr] ?? [];

                    DateTime parsedDate = DateTime.parse(dateStr);
                    String formattedDateHeader = DateFormat(
                      'dd MMM yyyy (EEEE)',
                    ).format(parsedDate);

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        title: Text(
                          formattedDateHeader,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal,
                          ),
                        ),
                        subtitle: Text(
                          'মোট উপস্থিত: ${dayRecords.length} জন',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        children: [
                          dayRecords.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Text(
                                    'এই তারিখে কোনো উপস্থিতি রেকর্ড পাওয়া যায়নি।',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: dayRecords.length,
                                  itemBuilder: (context, rIndex) {
                                    final record = dayRecords[rIndex];
                                    String name =
                                        record['teacher_name'] ?? 'শিক্ষক';
                                    String status =
                                        record['status'] ?? 'Present';
                                    String tStr = '';
                                    if (record['check_in_time'] != null) {
                                      DateTime t = DateTime.parse(
                                        record['check_in_time'],
                                      );
                                      DateTime bdT = t.isUtc
                                          ? t.add(const Duration(hours: 6))
                                          : t;
                                      tStr = DateFormat('hh:mm a').format(bdT);
                                    }

                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(
                                        Icons.person_outline,
                                        size: 20,
                                        color: Colors.teal,
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'সময়: $tStr',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: Chip(
                                        label: Text(
                                          status,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: status == 'Late'
                                            ? Colors.amber.shade800
                                            : Colors.green,
                                        padding: EdgeInsets.zero,
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
    );
  }
}
