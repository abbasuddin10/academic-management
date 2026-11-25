import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/result_calculator.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Student-facing result dashboard. Read-only: all marks/rank math is delegated
/// to [ResultCalculator] so it matches the admin view exactly.
class StudentResultView extends StatefulWidget {
  final String academyId;
  final String className;
  final String studentRoll;
  final String studentName;

  const StudentResultView({
    super.key,
    required this.academyId,
    required this.className,
    required this.studentRoll,
    required this.studentName,
  });

  @override
  State<StudentResultView> createState() => _StudentResultViewState();
}

class _StudentResultViewState extends State<StudentResultView> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _myResults = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allResults = <Map<String, dynamic>>[];

  final Set<String> _collapsedExams = <String>{};
  String? _examFilter;

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadResults();
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) setState(() => _isBannerAdLoaded = true);
      });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------
  Future<void> _loadResults() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var academyId = widget.academyId.trim();
      if (academyId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        academyId = prefs.getString('student_academy_id') ?? '';
      }
      if (academyId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'প্রতিষ্ঠানের তথ্য পাওয়া যায়নি। অনুগ্রহ করে আবার লগইন করুন।';
        });
        return;
      }

      // Fetch by academy only, then match roll + scope ranks in Dart. This
      // avoids false "no results" from class-name formatting differences.
      final response = await supabase
          .from('exam_results')
          .select()
          .eq('academy_id', academyId);

      final all = List<Map<String, dynamic>>.from(response);
      final mine = all
          .where(
            (row) => ResultCalculator.sameRoll(
              row['roll']?.toString(),
              widget.studentRoll,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _allResults = all;
        _myResults = mine;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching student results: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'ফলাফল লোড করা যায়নি। ইন্টারনেট সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
      });
    }
  }

  List<String> get _examTitles {
    final titles = <String>{};
    for (final row in _myResults) {
      final title = row['exam_title']?.toString().trim() ?? '';
      if (title.isNotEmpty) titles.add(title);
    }
    return titles.toList()..sort();
  }

  List<Map<String, dynamic>> get _visibleResults {
    if (_examFilter == null || _examFilter!.isEmpty) return _myResults;
    return _myResults
        .where((row) => row['exam_title']?.toString() == _examFilter)
        .toList();
  }

  List<Map<String, dynamic>> _peersFor(Map<String, dynamic> row) {
    final examTitle = row['exam_title']?.toString() ?? '';
    final className =
        row['class_name']?.toString().trim().isNotEmpty == true
            ? row['class_name']!.toString()
            : widget.className;
    return ResultCalculator.peersFor(
      allResults: _allResults,
      examTitle: examTitle,
      className: className,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceOf(context),
      appBar: AppBar(
        title: const Text('পরীক্ষার ফলাফল'),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading && _errorMessage == null && _myResults.isNotEmpty)
            IconButton(
              tooltip: 'রিফ্রেশ',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadResults,
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
          ? _buildError()
          : _myResults.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _loadResults,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 18),
                  _buildSectionTitle('পরীক্ষা নির্বাচন করুন'),
                  const SizedBox(height: 8),
                  _buildFilterChips(),
                  const SizedBox(height: 16),
                  _buildSectionTitle('বিস্তারিত ফলাফল'),
                  const SizedBox(height: 6),
                  ..._visibleResults.map(_buildExamCard),
                ],
              ),
            ),
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildLoading() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 14),
        Text('ফলাফল লোড হচ্ছে...', style: TextStyle(fontSize: 13)),
      ],
    ),
  );

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: AppTheme.mutedOf(context),
          ),
          const SizedBox(height: 16),
          Text(
            'এই মুহূর্তে আপনার কোনো পরীক্ষার ফলাফল পাওয়া যায়নি।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.mutedOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ফলাফল প্রকাশিত হলে এখানে দেখা যাবে।',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.mutedOf(context)),
          ),
        ],
      ),
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 60, color: AppTheme.errorOf(context)),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.inkOf(context)),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandOf(context),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _loadResults,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('আবার চেষ্টা করুন'),
          ),
        ],
      ),
    ),
  );

  Widget _buildSectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppTheme.inkOf(context),
    ),
  );

  Widget _buildSummaryCard() {
    var totalObtained = 0.0;
    var totalFull = 0.0;
    var bestRank = 999;
    final percentages = <double>[];

    for (final row in _myResults) {
      final data = ResultCalculator.mapOf(row['result_data']);
      final fullData = ResultCalculator.mapOf(row['full_marks_data']);
      totalObtained += ResultCalculator.obtainedMarks(data);
      totalFull += ResultCalculator.fullMarks(data, fullData);
      percentages.add(ResultCalculator.percentage(data, fullData).value);

      final rankText = ResultCalculator.examRank(
        _peersFor(row),
        row['roll']?.toString() ?? widget.studentRoll,
      );
      final rankNumber = int.tryParse(rankText.replaceAll(RegExp(r'[^0-9]'), ''));
      if (rankNumber != null && rankNumber < bestRank) bestRank = rankNumber;
    }

    final overall = percentages.isEmpty
        ? 0.0
        : percentages.reduce((a, b) => a + b) / percentages.length;
    final overallLabel = '${(overall * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, Colors.indigo),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.tileOf(context, Colors.indigo)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded,
                  size: 18, color: AppTheme.tileInkOf(context, Colors.indigo)),
              const SizedBox(width: 8),
              Text(
                'একাডেমিক সারাংশ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.tileInkOf(context, Colors.indigo),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: overall,
                      backgroundColor:
                          AppTheme.surfaceOf(context).withValues(alpha: 0.5),
                      color: AppTheme.tileInkOf(context, Colors.indigo),
                      strokeWidth: 7,
                    ),
                    Center(
                      child: Text(
                        overallLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.tileInkOf(context, Colors.indigo),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'সামগ্রিক কৃতিত্ব',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totalObtained.round()} / ${totalFull.round()} নম্বর',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildMiniChip(Icons.quiz_outlined,
                            '${_myResults.length} টি পরীক্ষা'),
                        if (bestRank < 999)
                          _buildMiniChip(
                            Icons.emoji_events_outlined,
                            'সেরা মেরিট: ${ResultCalculator.ordinal(bestRank)}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context).withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.tileInkOf(context, Colors.indigo)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.inkOf(context),
          ),
        ),
      ],
    ),
  );

  Widget _buildFilterChips() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      ChoiceChip(
        label: const Text('সব'),
        selected: _examFilter == null,
        onSelected: (_) => setState(() => _examFilter = null),
      ),
      ..._examTitles.map(
        (title) => ChoiceChip(
          label: Text(title, overflow: TextOverflow.ellipsis),
          selected: _examFilter == title,
          onSelected: (_) => setState(() => _examFilter = title),
        ),
      ),
    ],
  );

  Widget _buildExamCard(Map<String, dynamic> row) {
    final examTitle = row['exam_title']?.toString().trim() ?? 'পরীক্ষা';
    final peers = _peersFor(row);
    final roll = row['roll']?.toString() ?? widget.studentRoll;
    final merit = ResultCalculator.examRank(peers, roll);
    final collapsed = _collapsedExams.contains(examTitle);
    final percent = ResultCalculator.percentageOfRow(row);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() {
              if (collapsed) {
                _collapsedExams.remove(examTitle);
              } else {
                _collapsedExams.add(examTitle);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          examTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.inkOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'অর্জিত: ${percent.label}  •  মেরিট: $merit',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.mutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: AppTheme.brandOf(context),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed) ...[
            Divider(height: 1, color: AppTheme.borderOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: _buildMarksTable(row, peers),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMarksTable(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> peers,
  ) {
    final data = ResultCalculator.mapOf(row['result_data']);
    final subjects = ResultCalculator.subjects(data);

    if (subjects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'এই পরীক্ষার নম্বর এখনো এন্ট্রি করা হয়নি।',
          style: TextStyle(fontSize: 13, color: AppTheme.mutedOf(context)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 580,
        child: Table(
          border: TableBorder.all(
            color: AppTheme.borderOf(context),
            width: 1,
          ),
          columnWidths: const {
            0: FlexColumnWidth(2.6),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
            5: FlexColumnWidth(1.2),
            6: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF1B365D)),
              children: const [
                _HeaderCell('বিষয়'),
                _HeaderCell('CQ'),
                _HeaderCell('MCQ'),
                _HeaderCell('ভিভা'),
                _HeaderCell('Prac'),
                _HeaderCell('Total'),
                _HeaderCell('Pos'),
              ],
            ),
            ...subjects.toList().asMap().entries.map((entry) {
              final subject = entry.value;
              final cq = ResultCalculator.mark(data, subject, 'cq');
              final mcq = ResultCalculator.mark(data, subject, 'mcq');
              final viva = ResultCalculator.mark(data, subject, 'viva');
              final practical = ResultCalculator.mark(data, subject, 'practical');
              final total = cq + mcq + viva + practical;
              final position =
                  ResultCalculator.subjectRank(peers, subject, total);

              return TableRow(
                decoration: BoxDecoration(
                  color: entry.key.isEven
                      ? AppTheme.altSurfaceOf(context)
                      : AppTheme.surfaceOf(context),
                ),
                children: [
                  _BodyCell(subject.toUpperCase(), bold: true),
                  _BodyCell('$cq'),
                  _BodyCell('$mcq'),
                  _BodyCell('$viva'),
                  _BodyCell('$practical'),
                  _BodyCell('$total', bold: true),
                  _BodyCell(position, bold: true, accent: true),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

class _BodyCell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool accent;
  const _BodyCell(this.text, {this.bold = false, this.accent = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: TextStyle(
        fontSize: 11,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: accent
            ? AppTheme.brandOf(context)
            : AppTheme.inkOf(context),
      ),
    ),
  );
}
