/// One salary payment made to a teacher/staff member.
class TeacherSalaryPayment {
  final String month;
  final String paymentDate;
  final double amount;
  final String createdAt;

  const TeacherSalaryPayment({
    required this.month,
    required this.paymentDate,
    required this.amount,
    required this.createdAt,
  });
}

/// All salary payments and profile details for one teacher/staff member.
class TeacherSalaryGroup {
  final String teacherId;
  final String name;
  final String role;
  final String phone;
  final String email;
  final double monthlySalary;
  final String joinedAt;
  final List<TeacherSalaryPayment> payments;
  final double totalPayable;
  final double totalDue;

  const TeacherSalaryGroup({
    required this.teacherId,
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
    required this.monthlySalary,
    required this.joinedAt,
    required this.payments,
    required this.totalPayable,
    required this.totalDue,
  });

  double get totalPaid =>
      payments.fold<double>(0.0, (sum, payment) => sum + payment.amount);
}

/// Aggregation used by the dedicated teacher salary history PDF report.
class TeacherSalaryHistoryReportData {
  final DateTime generatedAt;
  final List<TeacherSalaryGroup> teachers;

  const TeacherSalaryHistoryReportData({
    required this.generatedAt,
    required this.teachers,
  });

  int get totalTeachers => teachers.length;

  double get totalDue =>
      teachers.fold<double>(0.0, (sum, teacher) => sum + teacher.totalDue);

  double get totalPaid =>
      teachers.fold<double>(0.0, (sum, teacher) => sum + teacher.totalPaid);

  double get totalMonthlySalary =>
      teachers.fold<double>(0.0, (sum, teacher) => sum + teacher.monthlySalary);
}

/// Metadata for a saved teacher salary history PDF. The file lives on device.
class SavedTeacherSalaryPdf {
  final String id;
  final String academyId;
  final String fileName;
  final String filePath;
  final DateTime generatedAt;
  final DateTime createdAt;
  final int fileSize;
  final int teacherCount;

  const SavedTeacherSalaryPdf({
    required this.id,
    required this.academyId,
    required this.fileName,
    required this.filePath,
    required this.generatedAt,
    required this.createdAt,
    required this.fileSize,
    required this.teacherCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'academyId': academyId,
    'fileName': fileName,
    'filePath': filePath,
    'generatedAt': generatedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'fileSize': fileSize,
    'teacherCount': teacherCount,
  };

  factory SavedTeacherSalaryPdf.fromJson(Map<String, dynamic> json) {
    return SavedTeacherSalaryPdf(
      id: json['id']?.toString() ?? '',
      academyId: json['academyId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'teacher_salary_history.pdf',
      filePath: json['filePath']?.toString() ?? '',
      generatedAt:
          DateTime.tryParse(json['generatedAt']?.toString() ?? '') ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fileSize: int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
      teacherCount: int.tryParse(json['teacherCount']?.toString() ?? '') ?? 0,
    );
  }
}
