import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/student_model_test_progress.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Rich, read-only progress report. Every figure comes from submitted official
/// attempts via `student_model_test_progress`; local practice never reaches it.
class StudentProgressDetailsView extends StatefulWidget {
  final String academyId;
  final String className;
  final StudentModelTestProgress? initialProgress;
  final ValueChanged<StudentModelTestProgress>? onProgressChanged;

  const StudentProgressDetailsView({
    super.key,
    required this.academyId,
    required this.className,
    this.initialProgress,
    this.onProgressChanged,
  });

  @override
  State<StudentProgressDetailsView> createState() =>
      _StudentProgressDetailsViewState();
}

class _StudentProgressDetailsViewState
    extends State<StudentProgressDetailsView> {
  final _repository = ModelTestRepository();

  late StudentModelTestProgress _progress;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Re-sanitise a late/cached payload, but do no network work here.
    _progress = StudentModelTestProgress.fromObject(widget.initialProgress);
    _loading = !_progress.hasResults;
    // Render the first frame with cached data, then refresh off that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(
          _refresh().catchError((Object error, StackTrace _) {
            _applyRefreshError(error);
          }),
        );
      } catch (error) {
        _applyRefreshError(error);
      }
    });
  }

  Future<void> _refresh() async {
    final academyId = widget.academyId.trim();
    final className = widget.className.trim();
    if (academyId.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'প্রতিষ্ঠানের তথ্য পাওয়া যায়নি। অনুগ্রহ করে আবার লগইন করুন।';
          _loading = false;
        });
      }
      return;
    }
    try {
      final progress = await _repository.fetchStudentProgress(
        academyId: academyId,
        className: className,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _error = null;
        _loading = false;
      });
      final callback = widget.onProgressChanged;
      if (callback != null) {
        try {
          callback(progress);
        } catch (_) {
          // A late parent refresh must never break this read-only screen.
        }
      }
    } catch (e) {
      _applyRefreshError(e);
    }
  }

  void _applyRefreshError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = ModelTestRepository.friendlyError(error);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep one malformed/huge payload from producing an unbounded column.
    final subjects = _progress.subjects.take(20).toList();
    final history = _progress.history.take(10).toList();
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: const Text('অগ্রগতির বিবরণ'),
        actions: [
          IconButton(
            tooltip: 'রিফ্রেশ',
            onPressed: _loading ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: _loading && !_progress.hasResults
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    if (_error != null) _buildErrorBanner(),
                    if (!_progress.hasResults)
                      _buildEmptyState()
                    else ...[
                      _buildOverallCard(),
                      const SizedBox(height: 14),
                      _buildInsights(),
                      const SizedBox(height: 18),
                      _buildSectionTitle(
                        icon: Icons.menu_book_outlined,
                        title: 'বিষয়ভিত্তিক ফলাফল',
                      ),
                      const SizedBox(height: 10),
                      if (subjects.isEmpty)
                        _buildSmallEmpty('এখনো বিষয়ভিত্তিক ফলাফল নেই।')
                      else ...[
                        ...subjects.map(_buildSubjectCard),
                        if (_progress.subjects.length > subjects.length)
                          _buildSmallEmpty('আরও বিষয় সংক্ষিপ্ত করা হয়েছে।'),
                      ],
                      const SizedBox(height: 18),
                      _buildSectionTitle(
                        icon: Icons.history,
                        title: 'সাম্প্রতিক পরীক্ষার ধারা',
                      ),
                      const SizedBox(height: 10),
                      _buildHistoryCard(history),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildErrorBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AppTheme.tileOf(context, Colors.orange),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: AppTheme.tileInkOf(context, Colors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'তথ্য রিফ্রেশ করা যায়নি। পুরনো ফলাফল দেখানো হচ্ছে। $_error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.tileInkOf(context, Colors.orange),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.borderOf(context)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.analytics_outlined,
          size: 52,
          color: AppTheme.mutedOf(context),
        ),
        const SizedBox(height: 14),
        Text(
          'এখনো কোনো সম্পন্ন পরীক্ষার ফলাফল নেই',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.inkOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'অফিশিয়াল পরীক্ষা জমা দেওয়ার পর এখানে গড় ফলাফল, '
          'বিষয়ভিত্তিক অবস্থান ও সাম্প্রতিক প্রবণতা দেখা যাবে।',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppTheme.mutedOf(context)),
        ),
      ],
    ),
  );

  Widget _buildOverallCard() {
    final overall = _progress.overall;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, Colors.indigo),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 19,
                color: AppTheme.tileInkOf(context, Colors.indigo),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ক্লাশে সামগ্রিক অবস্থান',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.tileInkOf(context, Colors.indigo),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _rankLabel(overall.rank, overall.totalStudents),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: AppTheme.tileInkOf(context, Colors.indigo),
            ),
          ),
          const SizedBox(height: 14),
          _infoRow(
            'মোট নম্বর',
            '${bnNum(_safeNumber(overall.totalScore))} / '
                '${bnNum(_safeNumber(overall.maxScore))}',
          ),
          const SizedBox(height: 7),
          _infoRow('গড় নম্বর', bnNum(_safeNumber(overall.averageScore))),
          const SizedBox(height: 7),
          _infoRow(
            'গড় শতাংশ',
            '${bnNum(_safePercent(overall.averagePercentage))}%',
          ),
          const SizedBox(height: 7),
          _infoRow('পাস রেট', '${bnNum(_safePercent(overall.passRate))}%'),
          const SizedBox(height: 7),
          _infoRow(
            'সঠিক / ভুল / খালি',
            '${bn(overall.correct)} / ${bn(overall.wrong)} / ${bn(overall.unanswered)}',
          ),
          const SizedBox(height: 7),
          _infoRow('মোট পরীক্ষা', bn(overall.testsTaken)),
        ],
      ),
    );
  }

  Widget _buildInsights() {
    final sorted = List<SubjectTestProgress>.from(_progress.subjects)
      ..sort(
        (a, b) => _safePercent(
          b.averagePercentage,
        ).compareTo(_safePercent(a.averagePercentage)),
      );
    final strongest = sorted.isEmpty ? null : sorted.first;
    final focus = sorted.length < 2 ? null : sorted.last;

    // A fixed height keeps this Row's cross-axis constraints finite inside the
    // unbounded ListView; stretched/expanded children cannot get h=Infinity.
    return SizedBox(
      height: 128,
      child: Row(
        children: [
          Expanded(
            child: _buildInsightCard(
              icon: Icons.trending_up_rounded,
              color: Colors.green,
              label: 'সবচেয়ে শক্ত বিষয়',
              subject: strongest,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildInsightCard(
              icon: Icons.trending_down_rounded,
              color: Colors.orange,
              label: 'মনোযোগ প্রয়োজন',
              subject: focus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required Color color,
    required String label,
    required SubjectTestProgress? subject,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.borderOf(context)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: AppTheme.mutedOf(context)),
        ),
        const SizedBox(height: 4),
        Text(
          subject == null ? 'পর্যাপ্ত তথ্য নেই' : subject.subjectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.inkOf(context),
          ),
        ),
        if (subject != null)
          Text(
            '${bnNum(_safePercent(subject.averagePercentage))}%',
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
      ],
    ),
  );

  Widget _buildSectionTitle({required IconData icon, required String title}) =>
      Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppTheme.tileInkOf(context, Colors.indigo),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.inkOf(context),
              ),
            ),
          ),
        ],
      );

  Widget _buildSubjectCard(SubjectTestProgress subject) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    color: AppTheme.surfaceOf(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: BorderSide(color: AppTheme.borderOf(context)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.book_outlined,
                size: 17,
                color: AppTheme.tileInkOf(context, Colors.teal),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  subject.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.inkOf(context),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 72),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.tileOf(context, _rankColor(subject.rank)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    subject.rank == null ? '—' : bnOrdinal(subject.rank!),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.tileInkOf(
                        context,
                        _rankColor(subject.rank),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
            'বিষয়ে পজিশন',
            _rankLabel(subject.rank, subject.totalStudents),
          ),
          const SizedBox(height: 6),
          _infoRow('মোট পরীক্ষা', bn(subject.testsTaken)),
          const SizedBox(height: 6),
          _infoRow(
            'নম্বর',
            '${bnNum(_safeNumber(subject.totalScore))} / '
                '${bnNum(_safeNumber(subject.maxScore))} '
                '(${bnNum(_safePercent(subject.averagePercentage))}%)',
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _fraction(subject.averagePercentage),
              minHeight: 7,
              backgroundColor: AppTheme.borderOf(context),
              color: _percentageColor(subject.averagePercentage),
            ),
          ),
          const SizedBox(height: 10),
          _infoRow(
            'সেরা',
            '${bnNum(_safeNumber(subject.bestScore))}/'
                '${bnNum(_safeNumber(subject.bestTotal))} '
                '(${bnNum(_safePercent(subject.bestPercentage))}%)',
          ),
          const SizedBox(height: 6),
          _infoRow(
            'সাম্প্রতিক',
            '${bnNum(_safeNumber(subject.latestScore))}/'
                '${bnNum(_safeNumber(subject.latestTotal))} '
                '(${bnNum(_safePercent(subject.latestPercentage))}%)',
          ),
        ],
      ),
    ),
  );

  Widget _buildHistoryCard(List<RecentTestProgress> rows) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: AppTheme.surfaceOf(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: BorderSide(color: AppTheme.borderOf(context)),
    ),
    child: rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(20),
            child: _buildSmallEmpty('এখনো সাম্প্রতিক ফলাফল নেই।'),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...rows.map(_buildHistoryRow),
              if (_progress.history.length > rows.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: _buildSmallEmpty('আরও কিছু পুরনো ফলাফল আছে।'),
                ),
            ],
          ),
  );

  Widget _buildHistoryRow(RecentTestProgress item) => ListTile(
    dense: true,
    leading: CircleAvatar(
      radius: 15,
      backgroundColor: AppTheme.tileOf(
        context,
        item.passed ? Colors.green : Colors.red,
      ),
      child: Icon(
        item.passed ? Icons.check : Icons.close,
        size: 15,
        color: AppTheme.tileInkOf(
          context,
          item.passed ? Colors.green : Colors.red,
        ),
      ),
    ),
    title: Text(
      item.subjectName.isEmpty
          ? item.title
          : '${item.subjectName} • ${item.title}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.inkOf(context),
      ),
    ),
    subtitle: Text(
      '${bnNum(_safeNumber(item.score))}/'
      '${bnNum(_safeNumber(item.totalMarks))} • '
      '${_formatDate(item.submittedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, color: AppTheme.mutedOf(context)),
    ),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 72),
      child: Text(
        '${bnNum(_safePercent(item.percentage))}%',
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _percentageColor(item.percentage),
        ),
      ),
    ),
  );

  Widget _infoRow(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: AppTheme.mutedOf(context)),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.inkOf(context),
          ),
        ),
      ),
    ],
  );

  Widget _buildSmallEmpty(String message) => Text(
    message,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12, color: AppTheme.mutedOf(context)),
  );

  double _safeNumber(double value, {double max = 1000000000}) {
    if (!value.isFinite) return 0;
    final bounded = value < 0 ? 0.0 : value;
    return bounded > max ? max : bounded;
  }

  double _safePercent(double value) => _safeNumber(value, max: 100);

  double _fraction(double percentage) =>
      (_safePercent(percentage) / 100).clamp(0.0, 1.0).toDouble();

  Color _percentageColor(double percentage) {
    final safe = _safePercent(percentage);
    if (safe >= 80) return Colors.green;
    if (safe >= 50) return Colors.orange;
    return AppTheme.errorOf(context);
  }

  Color _rankColor(int? rank) =>
      rank != null && rank >= 1 && rank <= 3 ? Colors.amber : Colors.teal;

  String _rankLabel(int? rank, int totalStudents) {
    if (rank == null || rank < 1) return 'এখনো ফলাফল নেই';
    final total = totalStudents > 0 ? ' / ${bn(totalStudents)} জন' : '';
    return '${bnOrdinal(rank)}$total';
  }

  String _formatDate(DateTime? time) {
    if (time == null) return '-';
    try {
      return DateFormat('dd MMM, yyyy').format(time.toLocal());
    } catch (_) {
      return '-';
    }
  }
}
