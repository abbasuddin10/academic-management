/// Typed result of the dashboard aggregation.
///
/// [toMap] keeps the historic key names so existing widgets can keep reading
/// the same values while data access lives in DashboardRepository.
class DashboardStats {
  final String? academyId;
  final int totalStudents;
  final double totalExpectedFee;
  final double totalDue;
  final double totalCollected;
  final double totalRemainingCollection;
  final String dateRange;
  final double totalTeacherSalary;
  final double paidTeacherSalary;
  final double remainingTeacherSalary;
  final double netBalance;
  final double totalOtherIncome;
  final double totalOtherExpense;
  final double ytdCollected;

  const DashboardStats({
    this.academyId,
    this.totalStudents = 0,
    this.totalExpectedFee = 0,
    this.totalDue = 0,
    this.totalCollected = 0,
    this.totalRemainingCollection = 0,
    this.dateRange = '',
    this.totalTeacherSalary = 0,
    this.paidTeacherSalary = 0,
    this.remainingTeacherSalary = 0,
    this.netBalance = 0,
    this.totalOtherIncome = 0,
    this.totalOtherExpense = 0,
    this.ytdCollected = 0,
  });

  static const empty = DashboardStats();

  static String _taka(double value, {required bool empty}) {
    if (empty && value == 0) return '৳ ০';
    return '৳ ${value.toStringAsFixed(0)}';
  }

  Map<String, dynamic> toMap() {
    final empty = academyId == null;
    return {
      'academyId': academyId,
      'totalStudents': totalStudents,
      'totalExpectedFee': _taka(totalExpectedFee, empty: empty),
      'totalDue': _taka(totalDue, empty: empty),
      'totalCollected': _taka(totalCollected, empty: empty),
      'totalRemainingCollection': _taka(totalRemainingCollection, empty: empty),
      'dateRange': dateRange,
      'totalTeacherSalary': _taka(totalTeacherSalary, empty: empty),
      'paidTeacherSalary': _taka(paidTeacherSalary, empty: empty),
      'remainingTeacherSalary': _taka(remainingTeacherSalary, empty: empty),
      'netBalance': _taka(netBalance, empty: empty),
      'totalOtherIncome': _taka(totalOtherIncome, empty: empty),
      'totalOtherExpense': _taka(totalOtherExpense, empty: empty),
      'ytdCollected': _taka(ytdCollected, empty: empty),
    };
  }
}
