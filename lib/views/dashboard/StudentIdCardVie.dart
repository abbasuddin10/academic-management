import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class StudentIdCardView extends StatefulWidget {
  final String academyId;

  const StudentIdCardView({super.key, required this.academyId});

  @override
  State<StudentIdCardView> createState() => _StudentIdCardViewState();
}

class _StudentIdCardViewState extends State<StudentIdCardView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isUploadingSign = false;
  bool _isDownloadingAll = false;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic> _academyInfo = {};
  String _selectedClass = 'সব ক্লাস';
  Map<String, int> _classCounts = {};
  List<String> _classList = [];

  // সার্চ কন্ট্রোলার
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final ScreenshotController _frontScreenshotController =
      ScreenshotController();
  final ScreenshotController _backScreenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final academyRes = await supabase
          .from('academies')
          .select()
          .eq('id', widget.academyId)
          .maybeSingle();

      if (academyRes != null) {
        _academyInfo = academyRes;
      }

      final studentRes = await supabase
          .from('students')
          .select('*')
          .eq('academy_id', widget.academyId);

      if (studentRes != null) {
        _students = List<Map<String, dynamic>>.from(studentRes);

        Map<String, int> counts = {};
        counts['সব ক্লাস'] = _students.length;

        Set<String> classes = {};
        for (var student in _students) {
          // ডেটাবেজে class বা class_name যেকোনো একটি থাকতে পারে, তাই উভয় চেক করা হলো
          String className = (student['class'] ?? student['class_name'] ?? '')
              .toString()
              .trim();
          if (className.isNotEmpty) {
            classes.add(className);
            counts[className] = (counts[className] ?? 0) + 1;
          }
        }

        _classCounts = counts;
        _classList = classes.toList();
        _classList.sort();
        _classList.insert(0, 'সব ক্লাস');
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadSignature() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      _isUploadingSign = true;
    });

    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName =
          'sign_${widget.academyId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = fileName;

      await supabase.storage
          .from('signatures')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExt',
            ),
          );

      final imageUrl = supabase.storage
          .from('signatures')
          .getPublicUrl(filePath);

      await supabase
          .from('academies')
          .update({'signature_url': imageUrl})
          .eq('id', widget.academyId);

      setState(() {
        _academyInfo['signature_url'] = imageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('সিগনেচার সফলভাবে আপলোড এবং সংরক্ষণ করা হয়েছে!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Signature upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('সিগনেচার আপলোড ব্যর্থ হয়েছে: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingSign = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ফিল্টারিং এবং সার্চ লজিক
    List<Map<String, dynamic>> filteredStudents = _students.where((student) {
      String className = (student['class'] ?? student['class_name'] ?? '')
          .toString()
          .trim();
      bool matchesClass =
          _selectedClass == 'সব ক্লাস' || className == _selectedClass;

      String name = (student['full_name'] ?? student['name'] ?? '')
          .toLowerCase();
      String roll = (student['roll']?.toString() ?? '').toLowerCase();
      String phone = (student['phone'] ?? '').toLowerCase();

      bool matchesSearch =
          _searchQuery.isEmpty ||
          name.contains(_searchQuery.toLowerCase()) ||
          roll.contains(_searchQuery.toLowerCase()) ||
          phone.contains(_searchQuery.toLowerCase());

      return matchesClass && matchesSearch;
    }).toList();

    String academyNameAr = _academyInfo['name_ar'] ?? '';
    String academyName =
        _academyInfo['name'] ?? _academyInfo['academy_name'] ?? 'মাদরাসার নাম';
    String academyAddress = _academyInfo['address'] ?? 'মাদরাসার ঠিকানা';
    String? academySignature =
        _academyInfo['signature_url'] ?? _academyInfo['signature'];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'স্টুডেন্ট স্মার্ট আইডি কার্ড',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0C5278),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // এক ক্লিকে সিলেক্টেড বা সমস্ত ক্লাসের আইডি কার্ড ডাউনলোড করার বাটন
          IconButton(
            icon: _isDownloadingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            tooltip: _selectedClass == 'সব ক্লাস'
                ? 'সকলের আইডি কার্ড ডাউনলোড'
                : '$_selectedClass এর সকল কার্ড ডাউনলোড',
            onPressed: (_isDownloadingAll || filteredStudents.isEmpty)
                ? null
                : () => _downloadMultiplePdf(
                    filteredStudents,
                    academyNameAr,
                    academyName,
                    academyAddress,
                    academySignature,
                  ),
          ),
          // সিগনেচার আপলোড বাটন
          IconButton(
            icon: _isUploadingSign
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.draw_rounded),
            tooltip: 'সিগনেচার আপলোড করুন',
            onPressed: _isUploadingSign ? null : _uploadSignature,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0C5278)),
            )
          : Column(
              children: [
                // সার্চ এবং হেডার সেকশন
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              'শিক্ষার্থীর নাম, রোল বা মোবাইল নম্বর দিয়ে খুঁজুন...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFF0C5278),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF4F6F9),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ক্লাস চিপস উইথ সঠিক কাউন্ট
                      SizedBox(
                        height: 42,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _classList.length,
                          itemBuilder: (context, index) {
                            String className = _classList[index];
                            bool isSelected = (className == _selectedClass);
                            int count = _classCounts[className] ?? 0;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text('$className ($count)'),
                                selected: isSelected,
                                selectedColor: const Color(0xFF0C5278),
                                backgroundColor: const Color(0xFFF4F6F9),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                onSelected: (bool selected) {
                                  setState(() {
                                    _selectedClass = className;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                // স্টুডেন্ট লিস্ট
                Expanded(
                  child: filteredStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 50,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'কোনো শিক্ষার্থী পাওয়া যায়নি!',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredStudents.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final student = filteredStudents[index];
                            String studentName =
                                student['full_name'] ??
                                student['name'] ??
                                'নামহীন';
                            String roll = student['roll']?.toString() ?? '';
                            String className =
                                student['class'] ??
                                student['class_name'] ??
                                'প্রযোজ্য নয়';
                            String? studentImg = student['image_url'];

                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF0C5278),
                                  foregroundColor: Colors.white,
                                  backgroundImage:
                                      (studentImg != null &&
                                          studentImg.isNotEmpty)
                                      ? NetworkImage(studentImg)
                                      : null,
                                  child:
                                      (studentImg == null || studentImg.isEmpty)
                                      ? Text(
                                          roll.isNotEmpty
                                              ? roll
                                              : '${index + 1}',
                                        )
                                      : null,
                                ),
                                title: Text(
                                  studentName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Text(
                                  'শ্রেণি: $className | রোল: ${roll.isNotEmpty ? roll : 'নেই'}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        color: Color(0xFF0C5278),
                                      ),
                                      tooltip: 'আইডি কার্ড দেখুন',
                                      onPressed: () {
                                        _showIdCardDialog(
                                          context,
                                          student,
                                          academyNameAr,
                                          academyName,
                                          academyAddress,
                                          academySignature,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        color: Color(0xFF2E7D32),
                                      ),
                                      tooltip: 'পিডিএফ ডাউনলোড করুন',
                                      onPressed: () {
                                        _downloadSinglePdf(
                                          context,
                                          student,
                                          academyNameAr,
                                          academyName,
                                          academyAddress,
                                          academySignature,
                                        );
                                      },
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
    );
  }

  void _showIdCardDialog(
    BuildContext context,
    Map<String, dynamic> student,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: _buildFrontCard(
                    student,
                    academyNameAr,
                    academyName,
                    academyAddress,
                    academySignature,
                  ),
                ),
                const SizedBox(height: 15),
                Center(
                  child: _buildBackCard(student, academyName, academyAddress),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text(
                    'বন্ধ করুন',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrontCard(
    Map<String, dynamic> student,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
  ) {
    String name = student['full_name'] ?? student['name'] ?? '';
    String fatherName = student['father_name'] ?? '';
    String className = student['class'] ?? student['class_name'] ?? '';
    String address = student['address'] ?? '';
    String phone = student['phone'] ?? '';
    String roll = student['roll']?.toString() ?? '';
    String? imageUrl = student['image_url'];

    return Container(
      width: 290,
      height: 450,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: const Color(0xFF0C5278), width: 2),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0C5278), Color(0xFF1B75BC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  if (academyNameAr.isNotEmpty)
                    Text(
                      academyNameAr,
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    academyName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    academyAddress,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0C5278), width: 2.5),
              image: (imageUrl != null && imageUrl.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: Colors.grey.shade100,
            ),
            child: (imageUrl == null || imageUrl.isEmpty)
                ? const Icon(Icons.person, size: 38, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0C5278),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 20.0, right: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('পিতার নাম', fatherName),
                _buildInfoRow('শ্রেণি/বিভাগ', className),
                _buildInfoRow('ঠিকানা', address),
                _buildInfoRow('মোবাইল', phone),
                _buildInfoRow('আইডি নং', roll),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: 28,
                      width: 85,
                      child:
                          (academySignature != null &&
                              academySignature.isNotEmpty)
                          ? Image.network(
                              academySignature,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(),
                            )
                          : const SizedBox(),
                    ),
                    Container(width: 85, height: 1, color: Colors.black54),
                    const SizedBox(height: 2),
                    const Text(
                      'প্রতিষ্ঠান প্রধানের স্বাক্ষর',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0C5278),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: const Center(
              child: Text(
                'STUDENT CARD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(
    Map<String, dynamic> student,
    String academyName,
    String academyAddress,
  ) {
    String name = student['full_name'] ?? student['name'] ?? '';
    String roll = student['roll']?.toString() ?? '';
    String className = student['class'] ?? student['class_name'] ?? '';
    String phone = student['phone'] ?? '';

    String qrData =
        'Name: $name\nID: $roll\nClass: $className\nPhone: $phone\nAcademy: $academyName';

    return Container(
      width: 290,
      height: 450,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: const Color(0xFF0C5278), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0C5278).withOpacity(0.05),
                border: Border.all(
                  color: const Color(0xFF0C5278).withOpacity(0.2),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'এই কার্ডটি ব্যবহারকারী ব্যতিত অন্য কেউ পেলে প্রতিষ্ঠানের ঠিকানায় পৌঁছে দেওয়ার জন্য অনুরোধ করা গেল।',
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.3,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF0C5278), width: 1.5),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 110.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0C5278),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              academyName,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0C5278),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              academyAddress,
              style: const TextStyle(fontSize: 8, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ইস্যু ও মেয়াদ :',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C5278),
                        ),
                      ),
                      Text(
                        '০১ জানুয়ারি - ৩১ ডিসেম্বর',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'শিক্ষাবর্ষ :',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C5278),
                        ),
                      ),
                      Text(
                        'চলমান কালীন',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
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
    );
  }

  // একক স্টুডেন্টের পিডিএফ ডাউনলোড
  Future<void> _downloadSinglePdf(
    BuildContext context,
    Map<String, dynamic> student,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF0C5278)),
      ),
    );

    try {
      final frontBytes = await _frontScreenshotController.captureFromWidget(
        Material(
          color: Colors.transparent,
          child: _buildFrontCard(
            student,
            academyNameAr,
            academyName,
            academyAddress,
            academySignature,
          ),
        ),
        pixelRatio: 3.0,
      );

      final backBytes = await _backScreenshotController.captureFromWidget(
        Material(
          color: Colors.transparent,
          child: _buildBackCard(student, academyName, academyAddress),
        ),
        pixelRatio: 3.0,
      );

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Image(pw.MemoryImage(frontBytes), width: 240, height: 380),
                  pw.SizedBox(width: 20),
                  pw.Image(pw.MemoryImage(backBytes), width: 240, height: 380),
                ],
              ),
            );
          },
        ),
      );

      if (mounted) Navigator.pop(context);

      String name = student['full_name'] ?? student['name'] ?? 'student';
      String className = student['class'] ?? student['class_name'] ?? 'general';
      String safeFileName = '${name}_$className'
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: '$safeFileName.pdf',
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("PDF Generation Error: $e");
    }
  }

  // স্মার্ট প্রোগ্রেস লোডার সহ একাধিক আইডি কার্ড ডাউনলোড
  Future<void> _downloadMultiplePdf(
    List<Map<String, dynamic>> students,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
  ) async {
    setState(() {
      _isDownloadingAll = true;
    });

    int totalStudents = students.length;
    ValueNotifier<int> progressNotifier = ValueNotifier<int>(0);

    // স্মার্ট লোডিং ডায়ালগ দেখানো
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0C5278)),
              const SizedBox(height: 16),
              const Text(
                'আইডি কার্ড তৈরি হচ্ছে...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0C5278),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: progressNotifier,
                builder: (context, value, child) {
                  return Text(
                    'মোট $totalStudents জনের মধ্যে $value জনের কার্ড প্রসেস করা হয়েছে',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'দয়া করে একটু অপেক্ষা করুন...',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final pdf = pw.Document();

      for (int i = 0; i < students.length; i++) {
        var student = students[i];

        final frontBytes = await _frontScreenshotController.captureFromWidget(
          Material(
            color: Colors.transparent,
            child: _buildFrontCard(
              student,
              academyNameAr,
              academyName,
              academyAddress,
              academySignature,
            ),
          ),
          pixelRatio: 2.5,
        );

        final backBytes = await _backScreenshotController.captureFromWidget(
          Material(
            color: Colors.transparent,
            child: _buildBackCard(student, academyName, academyAddress),
          ),
          pixelRatio: 2.5,
        );

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Image(
                      pw.MemoryImage(frontBytes),
                      width: 230,
                      height: 360,
                    ),
                    pw.SizedBox(width: 20),
                    pw.Image(
                      pw.MemoryImage(backBytes),
                      width: 230,
                      height: 360,
                    ),
                  ],
                ),
              );
            },
          ),
        );

        progressNotifier.value = i + 1; // কাউন্টার আপডেট
      }

      if (mounted) Navigator.pop(context); // ডায়ালগ বন্ধ

      String safeFileName = '${_selectedClass}_All_Id_Cards'
          .replaceAll(RegExp(r'[^\w\u0980-\u09FF\s]+'), '')
          .replaceAll(' ', '_');

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: '$safeFileName.pdf',
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Multiple PDF Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAll = false;
        });
      }
    }
  }
}
