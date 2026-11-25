/// One student with unpaid fee months in the due-students PDF report.
class DueStudentRecord {
  final String studentId;
  final String name;
  final String fatherName;
  final String roll;
  final String className;
  final double monthlyFee;
  final List<String> pendingMonths;
  final double dueAmount;

  const DueStudentRecord({
    required this.studentId,
    required this.name,
    required this.fatherName,
    required this.roll,
    required this.className,
    required this.monthlyFee,
    required this.pendingMonths,
    required this.dueAmount,
  });
}

/// All due students belonging to one class.
class DueClassGroup {
  final String className;
  final List<DueStudentRecord> students;

  const DueClassGroup({required this.className, required this.students});

  int get studentCount => students.length;

  double get dueAmount =>
      students.fold<double>(0.0, (sum, student) => sum + student.dueAmount);

  /// Unique pending months across the class, in first-seen order.
  List<String> get pendingMonths {
    final seen = <String>{};
    final months = <String>[];
    for (final student in students) {
      for (final month in student.pendingMonths) {
        if (seen.add(month)) months.add(month);
      }
    }
    return months;
  }
}

/// Class-wise aggregation used by the dedicated due-students PDF report.
class DueStudentsReportData {
  final DateTime generatedAt;
  final List<DueClassGroup> classes;

  const DueStudentsReportData({
    required this.generatedAt,
    required this.classes,
  });

  int get totalClasses => classes.length;

  int get totalStudents =>
      classes.fold<int>(0, (sum, group) => sum + group.studentCount);

  double get totalDueAmount =>
      classes.fold<double>(0.0, (sum, group) => sum + group.dueAmount);

  int get totalPendingMonths {
    final seen = <String>{};
    for (final group in classes) {
      seen.addAll(group.pendingMonths);
    }
    return seen.length;
  }
}

/// Metadata for a saved due-students PDF. The PDF itself lives on the device.
class SavedDueStudentsPdf {
  final String id;
  final String academyId;
  final String fileName;
  final String filePath;
  final DateTime generatedAt;
  final DateTime createdAt;
  final int fileSize;
  final int studentCount;
  final int classCount;

  const SavedDueStudentsPdf({
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

  factory SavedDueStudentsPdf.fromJson(Map<String, dynamic> json) {
    return SavedDueStudentsPdf(
      id: json['id']?.toString() ?? '',
      academyId: json['academyId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'due_students_report.pdf',
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
