/// One student row in the complete all-students PDF report.
///
/// The full Supabase row is kept so no available column is lost when the PDF
/// is rendered; the typed fields only drive grouping and ordering.
class AllStudentRecord {
  final Map<String, dynamic> raw;
  final String studentId;
  final String name;
  final String roll;
  final String className;

  const AllStudentRecord({
    required this.raw,
    required this.studentId,
    required this.name,
    required this.roll,
    required this.className,
  });

  String get fatherName =>
      _firstText(const ['father_name', 'guardian_name'], 'পাওয়া যায়নি');

  String get phone => _firstText(const ['phone', 'mobile'], 'নেই');

  double get monthlyFee =>
      double.tryParse(raw['monthly_fee']?.toString() ?? '') ?? 0.0;

  String _firstText(List<String> keys, String fallback) {
    for (final key in keys) {
      final value = raw[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }
}

/// Every student belonging to one class.
class AllStudentClassGroup {
  final String className;
  final List<AllStudentRecord> students;

  const AllStudentClassGroup({required this.className, required this.students});

  int get studentCount => students.length;

  double get monthlyFeeTotal =>
      students.fold<double>(0.0, (sum, student) => sum + student.monthlyFee);
}

/// Class-wise aggregation used by the dedicated all-students PDF report.
class AllStudentsReportData {
  final DateTime generatedAt;
  final List<AllStudentClassGroup> classes;

  const AllStudentsReportData({
    required this.generatedAt,
    required this.classes,
  });

  int get totalClasses => classes.length;

  int get totalStudents =>
      classes.fold<int>(0, (sum, group) => sum + group.studentCount);

  double get totalMonthlyFee =>
      classes.fold<double>(0.0, (sum, group) => sum + group.monthlyFeeTotal);
}

/// Metadata for a saved all-students PDF. The PDF itself lives on the device.
class SavedAllStudentsPdf {
  final String id;
  final String academyId;
  final String fileName;
  final String filePath;
  final DateTime generatedAt;
  final DateTime createdAt;
  final int fileSize;
  final int studentCount;
  final int classCount;

  const SavedAllStudentsPdf({
    required this.id,
    required this.academyId,
    required this.fileName,
    required this.filePath,
    required this.generatedAt,
    required this.createdAt,
    required this.fileSize,
    required this.studentCount,
    required this.classCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'academyId': academyId,
    'fileName': fileName,
    'filePath': filePath,
    'generatedAt': generatedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'fileSize': fileSize,
    'studentCount': studentCount,
    'classCount': classCount,
  };

  factory SavedAllStudentsPdf.fromJson(Map<String, dynamic> json) {
    return SavedAllStudentsPdf(
      id: json['id']?.toString() ?? '',
      academyId: json['academyId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'all_students_report.pdf',
      filePath: json['filePath']?.toString() ?? '',
      generatedAt:
          DateTime.tryParse(json['generatedAt']?.toString() ?? '') ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fileSize: int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
      studentCount: int.tryParse(json['studentCount']?.toString() ?? '') ?? 0,
      classCount: int.tryParse(json['classCount']?.toString() ?? '') ?? 0,
    );
  }
}
