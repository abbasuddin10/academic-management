/// A single itemised income/expense entry used by the financial PDF report.
class FinancialTransaction {
  final DateTime date;
  final String category;
  final bool isIncome;
  final double amount;
  final String? note;

  const FinancialTransaction({
    required this.date,
    required this.category,
    required this.isIncome,
    required this.amount,
    this.note,
  });
}

/// All transactions for one selected date/time window plus derived totals.
class FinancialReportData {
  final DateTime start;
  final DateTime end;
  final List<FinancialTransaction> transactions;

  const FinancialReportData({
    required this.start,
    required this.end,
    required this.transactions,
  });

  double get totalIncome => transactions
      .where((item) => item.isIncome)
      .fold<double>(0.0, (sum, item) => sum + item.amount);

  double get totalExpense => transactions
      .where((item) => !item.isIncome)
      .fold<double>(0.0, (sum, item) => sum + item.amount);

  double get netBalance => totalIncome - totalExpense;

  int get entryCount => transactions.length;
}

/// Metadata for a generated PDF stored on the device.
///
/// Only the metadata lives in SharedPreferences; the PDF itself lives in the
/// device Downloads/Documents folder so it can be opened or shared from there.
class SavedFinancialPdf {
  final String id;
  final String academyId;
  final String fileName;
  final String filePath;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime createdAt;
  final int fileSize;

  const SavedFinancialPdf({
    required this.id,
    required this.academyId,
    required this.fileName,
    required this.filePath,
    required this.startAt,
    required this.endAt,
    required this.createdAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'academyId': academyId,
    'fileName': fileName,
    'filePath': filePath,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'fileSize': fileSize,
  };

  factory SavedFinancialPdf.fromJson(Map<String, dynamic> json) {
    return SavedFinancialPdf(
      id: json['id']?.toString() ?? '',
      academyId: json['academyId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'report.pdf',
      filePath: json['filePath']?.toString() ?? '',
      startAt:
          DateTime.tryParse(json['startAt']?.toString() ?? '') ??
          DateTime.now(),
      endAt:
          DateTime.tryParse(json['endAt']?.toString() ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fileSize: int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
    );
  }
}
