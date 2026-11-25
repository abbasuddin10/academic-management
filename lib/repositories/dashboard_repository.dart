import 'package:academy_management/models/dashboard_stats.dart';
import 'academy_repository.dart';
import 'base_repository.dart';

/// Owns every Supabase query used to build the admin dashboard statistics.
class DashboardRepository extends BaseRepository {
  static const List<String> _months = [
    'জানুয়ারি',
    'ফেব্রুয়ারি',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টেম্বর',
    'অক্টোবর',
    'নভেম্বর',
    'ডিসেম্বর',
  ];

  Future<DashboardStats> fetchStats() async {
    try {
      final email = client.auth.currentUser?.email;
      if (email == null || email.isEmpty) return DashboardStats.empty;

      final academyId = await AcademyRepository().currentUserAcademyId();
      if (academyId == null || academyId.isEmpty) {
        return DashboardStats.empty;
      }

      final students = await client
          .from('students')
          .select('monthly_fee')
          .eq('academy_id', academyId);
      var totalExpectedFee = 0.0;
      for (final student in (students as List)) {
        totalExpectedFee +=
            double.tryParse(student['monthly_fee']?.toString() ?? '') ?? 0;
      }

      final teachers = await client
          .from('users')
          .select('salary, created_at')
          .eq('academy_id', academyId)
          .inFilter('role', ['teacher', 'super_admin']);

      final now = DateTime.now();
      var oneMonthSalary = 0.0;
      var accruedSalary = 0.0;
      for (final teacher in (teachers as List)) {
        final salary =
            double.tryParse(teacher['salary']?.toString() ?? '') ?? 0;
        oneMonthSalary += salary;

        final createdAt = DateTime.tryParse(teacher['created_at']?.toString() ?? '');
        if (createdAt == null) {
          accruedSalary += salary;
          continue;
        }
        final joined = createdAt.toLocal();
        var months =
            (now.year - joined.year) * 12 + now.month - joined.month;
        if (months < 0) months = 0;
        accruedSalary += salary * (months + 1);
      }

      final salaryHistory = await client
          .from('teacher_salary_history')
          .select('amount')
          .eq('academy_id', academyId);
      var paidSalary = 0.0;
      for (final item in (salaryHistory as List)) {
        paidSalary += double.tryParse(item['amount']?.toString() ?? '') ?? 0;
      }
      var remainingSalary = accruedSalary - paidSalary;
      if (remainingSalary < 0) remainingSalary = 0;

      var previousMonth = now.month - 1;
      var previousYear = now.year;
      if (previousMonth == 0) {
        previousMonth = 12;
        previousYear -= 1;
      }
      final startDate = DateTime(previousYear, previousMonth, 10);
      final endDate = DateTime(now.year, now.month, 10, 23, 59, 59);
      final dateRange =
          '${startDate.day} ${_months[startDate.month - 1]} থেকে ${endDate.day} ${_months[endDate.month - 1]}';

      final feeHistory = await client
          .from('student_fee_history')
          .select('amount, created_at')
          .eq('academy_id', academyId);

      var collected = 0.0;
      var ytdCollected = 0.0;
      for (final item in (feeHistory as List)) {
        final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
        if (createdAt == null) continue;
        final local = createdAt.toLocal();
        final amount = double.tryParse(item['amount']?.toString() ?? '') ?? 0;

        if (!local.isBefore(startDate.subtract(const Duration(seconds: 1))) &&
            !local.isAfter(endDate.add(const Duration(seconds: 1)))) {
          collected += amount;
        }
        if (local.year == now.year && local.month <= now.month) {
          ytdCollected += amount;
        }
      }

      var otherIncome = 0.0;
      var otherExpense = 0.0;
      try {
        final rows = await client
            .from('other_income_expenses')
            .select('amount, type, created_at')
            .eq('academy_id', academyId);
        for (final item in (rows as List)) {
          final local = DateTime.tryParse(item['created_at']?.toString() ?? '')
              ?.toLocal();
          if (local == null ||
              local.year != now.year ||
              local.month > now.month) {
            continue;
          }
          final amount = double.tryParse(item['amount']?.toString() ?? '') ?? 0;
          final type = item['type']?.toString().toLowerCase().trim() ?? '';
          if (type == 'income' || type == 'আয়' || type == 'آئ') {
            otherIncome += amount;
          } else if (type == 'expense' ||
              type == 'ব্যয়' ||
              type == 'cost') {
            otherExpense += amount;
          }
        }
      } catch (e) {
        // Partial data is preferable to failing the whole dashboard.
      }

      var otherCollections = 0.0;
      try {
        final rows = await client
            .from('student_other_collections')
            .select('amount, payment_date, created_at')
            .eq('academy_id', academyId);
        for (final item in (rows as List)) {
          final dateStr =
              item['payment_date'] ?? item['created_at']?.toString();
          final local = DateTime.tryParse(dateStr?.toString() ?? '')?.toLocal();
          if (local == null ||
              local.year != now.year ||
              local.month > now.month) {
            continue;
          }
          otherCollections +=
              double.tryParse(item['amount']?.toString() ?? '') ?? 0;
        }
      } catch (e) {
        // Partial data is preferable to failing the whole dashboard.
      }

      final totalOtherIncome = otherIncome + otherCollections;
      final grandIncome = ytdCollected + totalOtherIncome;
      final grandExpense = paidSalary + otherExpense;

      var due = totalExpectedFee - collected;
      if (due < 0) due = 0;

      return DashboardStats(
        academyId: academyId,
        totalStudents: students.length,
        totalExpectedFee: totalExpectedFee,
        totalDue: due,
        totalCollected: collected,
        totalRemainingCollection: due,
        dateRange: dateRange,
        totalTeacherSalary: oneMonthSalary,
        paidTeacherSalary: paidSalary,
        remainingTeacherSalary: remainingSalary,
        netBalance: grandIncome - grandExpense,
        totalOtherIncome: totalOtherIncome,
        totalOtherExpense: otherExpense,
        ytdCollected: ytdCollected,
      );
    } catch (e) {
      return DashboardStats.empty;
    }
  }
}
