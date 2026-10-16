import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:image_picker/image_picker.dart';

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

      _students = List<Map<String, dynamic>>.from(studentRes);

      Map<String, int> counts = {};
      counts['সব ক্লাস'] = _students.length;

      Set<String> classes = {};
      for (var student in _students) {
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
    String? logoUrl = _academyInfo['logo_url'];

    // ডাটাবেজ থেকে অতিরিক্ত তথ্যসমূহ সংগ্রহ করা হলো
    String academyPhone = _academyInfo['phone']?.toString() ?? '';
    String academyEmail = _academyInfo['admin_email']?.toString() ?? '';
    String academyEiin = _academyInfo['eiin']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'স্টুডেন্ট স্মার্ট আইডি কার্ড',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF2993D2),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
                    logoUrl,
                    academyPhone,
                    academyEmail,
                    academyEiin,
                  ),
          ),
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
              child: CircularProgressIndicator(color: Color(0xFF2993D2)),
            )
          : Column(
              children: [
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
                            color: Color(0xFF2993D2),
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
                                selectedColor: const Color(0xFF2993D2),
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
                                  backgroundColor: const Color(0xFF2993D2),
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
                                        color: Color(0xFF2993D2),
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
                                          logoUrl,
                                          academyPhone,
                                          academyEmail,
                                          academyEiin,
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
                                          logoUrl,
                                          academyPhone,
                                          academyEmail,
                                          academyEiin,
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
    String? logoUrl,
    String academyPhone,
    String academyEmail,
    String academyEiin,
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
                  child: Screenshot(
                    controller: _frontScreenshotController,
                    child: _buildFrontCard(
                      student,
                      academyNameAr,
                      academyName,
                      academyAddress,
                      academySignature,
                      logoUrl,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Center(
                  child: Screenshot(
                    controller: _backScreenshotController,
                    child: _buildBackCard(
                      student,
                      academyName,
                      academyAddress,
                      logoUrl,
                      academyPhone,
                      academyEmail,
                      academyEiin,
                    ),
                  ),
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
    String? logoUrl,
  ) {
    String name = student['full_name'] ?? student['name'] ?? '';
    String roll = student['roll']?.toString() ?? '';
    String className = student['class'] ?? student['class_name'] ?? '';
    String fatherName = student['father_name'] ?? '';
    String phone = student['phone'] ?? '';
    String address = student['address'] ?? '';
    String? imageUrl = student['image_url'];

    return Container(
      width: 230,
      height: 360,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: CustomPaint(painter: ExactTopVectorPainter()),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 35,
              child: CustomPaint(painter: ExactBottomVectorPainter()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty)
                        Image.network(
                          logoUrl,
                          height: 16,
                          width: 16,
                          fit: BoxFit.fill,
                        )
                      else
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          academyName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00AEEF),
                        width: 3,
                      ),
                      image: (imageUrl != null && imageUrl.isNotEmpty)
                          ? DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: Colors.grey.shade200,
                    ),
                    child: (imageUrl == null || imageUrl.isEmpty)
                        ? const Icon(Icons.person, size: 38, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name.isNotEmpty ? name : 'Your Name Here',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    className.isNotEmpty
                        ? 'Class: $className'
                        : 'Designation Here',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF00AEEF),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('ID No', roll.isNotEmpty ? roll : '123456'),
                  _buildInfoRow(
                    'Father',
                    fatherName.isNotEmpty ? fatherName : 'N/A',
                  ),
                  _buildInfoRow(
                    'Phone',
                    phone.isNotEmpty ? phone : '0000000000',
                  ),
                  _buildInfoRow(
                    'Address',
                    address.isNotEmpty ? address : 'N/A',
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 45.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.black87,
                              width: 0.8,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.qr_code_2_rounded,
                              size: 34,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (academySignature != null &&
                                academySignature.isNotEmpty)
                              SizedBox(
                                height: 20,
                                width: 65,
                                child: Image.network(
                                  academySignature,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else
                              const SizedBox(height: 20),
                            Container(
                              width: 75,
                              height: 1,
                              color: Colors.black87,
                              margin: const EdgeInsets.only(bottom: 2),
                            ),
                            const Text(
                              'প্রধান শিক্ষক/অধ্যক্ষ',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B1B4B),
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
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B1B4B),
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B1B4B),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
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
    String? logoUrl,
    String academyPhone,
    String academyEmail,
    String academyEiin,
  ) {
    return Container(
      width: 230,
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2993D2), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: ExactBackCurvePainter()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15.0,
                vertical: 15.0,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // ওপরে নির্দেশিকা টেক্সট
                  const Text(
                    'এই কার্ডটি ব্যবহারকারী ব্যতিত অন্য কেউ পেলে প্রতিষ্ঠানের ঠিকানায় পৌঁছে দেওয়ার জন্য অনুরোধ করা গেল।',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // লোগো
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF2993D2),
                        width: 1.2,
                      ),
                      image: (logoUrl != null && logoUrl.isNotEmpty)
                          ? DecorationImage(
                              image: NetworkImage(logoUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: Colors.grey.shade200,
                    ),
                    child: (logoUrl == null || logoUrl.isEmpty)
                        ? const Icon(Icons.school, size: 22, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  // মাদ্রাসার নাম (বোল্ড ও আকর্ষণীয় ডিজাইন)
                  Text(
                    academyName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B1B4B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  // ঠিকানা
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 9,
                        color: Color(0xFF2993D2),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          academyAddress,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // প্রতিষ্ঠানের আইডি ভিত্তিক অতিরিক্ত ইনফো (ফোন, ইমেইল, EIIN) সুন্দরভাবে সাজানো
                  // প্রতিষ্ঠানের আইডি ভিত্তিক অতিরিক্ত ইনফো (টেবিলের মতো সিরিয়ালে সাজানো)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (academyPhone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  size: 8,
                                  color: Color(0xFF2993D2),
                                ),
                                const SizedBox(width: 4),
                                const SizedBox(
                                  width: 32,
                                  child: Text(
                                    'ফোন',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ': ',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    academyPhone,
                                    style: const TextStyle(
                                      fontSize: 7.5,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (academyEmail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.email,
                                  size: 8,
                                  color: Color(0xFF2993D2),
                                ),
                                const SizedBox(width: 4),
                                const SizedBox(
                                  width: 32,
                                  child: Text(
                                    'ইমেইল',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ': ',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    academyEmail,
                                    style: const TextStyle(
                                      fontSize: 7.5,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (academyEiin.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified,
                                  size: 8,
                                  color: Color(0xFF2993D2),
                                ),
                                const SizedBox(width: 4),
                                const SizedBox(
                                  width: 32,
                                  child: Text(
                                    'EIIN',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ': ',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    academyEiin,
                                    style: const TextStyle(
                                      fontSize: 7.5,
                                      color: Color(0xFF1B1B4B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // নোট বক্স
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black54, width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'রাষ্ট্রদ্রোহী কাজে জড়িত না থাকার শর্তে শুধুমাত্র অধ্যয়নকালীন সময়ের জন্য প্রযোজ্য।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // ইস্যু তারিখ ও মেয়াদ কাল
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ইস্যু তারিখঃ  01/01/${DateTime.now().year} ইং',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'মেয়াদ কালঃ   31/12/${DateTime.now().year} ইং',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 25),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadSinglePdf(
    BuildContext context,
    Map<String, dynamic> student,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
    String? logoUrl,
    String academyPhone,
    String academyEmail,
    String academyEiin,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2993D2)),
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
            logoUrl,
          ),
        ),
        pixelRatio: 3.0,
      );

      final backBytes = await _backScreenshotController.captureFromWidget(
        Material(
          color: Colors.transparent,
          child: _buildBackCard(
            student,
            academyName,
            academyAddress,
            logoUrl,
            academyPhone,
            academyEmail,
            academyEiin,
          ),
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
                  pw.Image(pw.MemoryImage(frontBytes), width: 230, height: 360),
                  pw.SizedBox(width: 20),
                  pw.Image(pw.MemoryImage(backBytes), width: 230, height: 360),
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

  Future<void> _downloadMultiplePdf(
    List<Map<String, dynamic>> students,
    String academyNameAr,
    String academyName,
    String academyAddress,
    String? academySignature,
    String? logoUrl,
    String academyPhone,
    String academyEmail,
    String academyEiin,
  ) async {
    setState(() {
      _isDownloadingAll = true;
    });

    int totalStudents = students.length;
    ValueNotifier<int> progressNotifier = ValueNotifier<int>(0);

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
              const CircularProgressIndicator(color: Color(0xFF2993D2)),
              const SizedBox(height: 16),
              const Text(
                'আইডি কার্ড তৈরি হচ্ছে...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF2993D2),
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
              logoUrl,
            ),
          ),
          pixelRatio: 2.5,
        );

        final backBytes = await _backScreenshotController.captureFromWidget(
          Material(
            color: Colors.transparent,
            child: _buildBackCard(
              student,
              academyName,
              academyAddress,
              logoUrl,
              academyPhone,
              academyEmail,
              academyEiin,
            ),
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

        progressNotifier.value = i + 1;
      }

      if (mounted) Navigator.pop(context);

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

// কাস্টম টপ ভেক্টর পেন্টার (ফ্রন্ট কার্ড)
class ExactTopVectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintDarkNavy = Paint()
      ..color = const Color(0xFF1B1B4B)
      ..style = PaintingStyle.fill;

    final paintCyan = Paint()
      ..color = const Color(0xFF00AEEF)
      ..style = PaintingStyle.fill;

    Path navyPath = Path();
    navyPath.moveTo(0, 0);
    navyPath.lineTo(size.width, 0);
    navyPath.lineTo(size.width, size.height * 0.82);
    navyPath.lineTo(size.width * 0.58, size.height * 0.64);
    navyPath.lineTo(size.width * 0.42, size.height * 0.64);
    navyPath.lineTo(0, size.height * 0.82);
    navyPath.close();
    canvas.drawPath(navyPath, paintDarkNavy);

    Path cyanPath = Path();
    cyanPath.moveTo(0, size.height * 0.82);
    cyanPath.lineTo(size.width * 0.42, size.height * 0.64);
    cyanPath.lineTo(size.width * 0.58, size.height * 0.64);
    cyanPath.lineTo(size.width, size.height * 0.82);
    cyanPath.lineTo(size.width, size.height * 0.97);
    cyanPath.lineTo(size.width * 0.58, size.height * 0.79);
    cyanPath.lineTo(size.width * 0.42, size.height * 0.79);
    cyanPath.lineTo(0, size.height * 0.97);
    cyanPath.close();
    canvas.drawPath(cyanPath, paintCyan);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ব্যাক পার্টের জন্য আরও ছোট ও আকর্ষণীয় কার্ভড স্কাই ব্লু শেপ পেন্টার
class ExactBackCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintBg = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final paintCyan = Paint()
      ..color = const Color(0xFF00AEEF).withOpacity(0.12);

    Path bgPath = Path();
    bgPath.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(bgPath, paintBg);

    // ওপরে এবং নিচে ছোট কার্ভড শেপ বা বর্ডার ইফেক্ট
    Path topCurve = Path();
    topCurve.lineTo(0, size.height * 0.12);
    topCurve.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.18,
      size.width,
      size.height * 0.12,
    );
    topCurve.lineTo(size.width, 0);
    topCurve.close();
    canvas.drawPath(topCurve, paintCyan);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// কাস্টম বটম ভেক্টর পেন্টার (ফ্রন্ট কার্ড)
class ExactBottomVectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintDarkSlate = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final paintBlue = Paint()
      ..color = const Color(0xFF2993D2)
      ..style = PaintingStyle.fill;

    final paintWhite = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    Path leftPath = Path();
    leftPath.addRect(Rect.fromLTWH(0, 0, size.width * 0.48, size.height));
    canvas.drawPath(leftPath, paintDarkSlate);

    Path rightPath = Path();
    rightPath.addRect(
      Rect.fromLTWH(size.width * 0.48, 0, size.width * 0.52, size.height),
    );
    canvas.drawPath(rightPath, paintBlue);

    Path stripe1 = Path();
    stripe1.moveTo(size.width * 0.40, size.height);
    stripe1.lineTo(size.width * 0.47, size.height);
    stripe1.lineTo(size.width * 0.55, 0);
    stripe1.lineTo(size.width * 0.48, 0);
    stripe1.close();
    canvas.drawPath(stripe1, paintWhite);

    Path stripe2 = Path();
    stripe2.moveTo(size.width * 0.52, size.height);
    stripe2.lineTo(size.width * 0.59, size.height);
    stripe2.lineTo(size.width * 0.67, 0);
    stripe2.lineTo(size.width * 0.60, 0);
    stripe2.close();
    canvas.drawPath(stripe2, paintWhite);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
