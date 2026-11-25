import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/financial_report.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/financial_report_service.dart';
import 'package:academy_management/widgets/async_state_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

/// One labelled value inside the two top summary cards.
class _SummaryMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

/// Admin screen for generating a date/time-filtered financial PDF and managing
/// the PDFs already saved on this device.
class FinancialPdfReportView extends StatefulWidget {
  final String academyId;

  const FinancialPdfReportView({super.key, required this.academyId});

  @override
  State<FinancialPdfReportView> createState() => _FinancialPdfReportViewState();
}

class _FinancialPdfReportViewState extends State<FinancialPdfReportView> {
  late final AppStateController _appState;
  Worker? _languageWorker;
  bool _isEnglish = false;

  late DateTime _start;
  late DateTime _end;
  String? _preset;

  FinancialReportData? _report;
  bool _isLoadingPreview = false;
  String? _previewError;

  bool _isGenerating = false;
  Uint8List? _lastBytes;

  List<SavedFinancialPdf> _saved = [];
  bool _isLoadingSaved = true;
  String? _savedError;

  @override
  void initState() {
    super.initState();
    _appState = Get.find<AppStateController>();
    _isEnglish = _appState.isEnglish.value;
    _languageWorker = ever(_appState.isEnglish, (value) {
      if (mounted) setState(() => _isEnglish = value);
    });

    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _preset = 'today';

    _refreshPreview();
    _loadSaved();
  }

  @override
  void dispose() {
    _languageWorker?.dispose();
    super.dispose();
  }

  String tr(String bangla, String english) => _isEnglish ? english : bangla;

  // ---------------------------------------------------------------------------
  // Date range handling
  // ---------------------------------------------------------------------------

  void _normalizeRange() {
    if (_end.isBefore(_start)) {
      _end = DateTime(_start.year, _start.month, _start.day, 23, 59, 59);
    }
  }

  void _applyPreset(String key) {
    final now = DateTime.now();
    setState(() {
      _preset = key;
      switch (key) {
        case '7days':
          _start = DateTime(now.year, now.month, now.day - 6);
          _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case 'month':
          _start = DateTime(now.year, now.month, 1);
          _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case 'year':
          _start = DateTime(now.year, 1, 1);
          _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case 'today':
        default:
          _start = DateTime(now.year, now.month, now.day);
          _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _refreshPreview();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: tr('তারিখ নির্বাচন করুন', 'Select a date'),
    );
    if (!mounted || picked == null) return;

    setState(() {
      if (isStart) {
        _start = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _start.hour,
          _start.minute,
          _start.second,
        );
      } else {
        _end = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _end.hour,
          _end.minute,
          _end.second,
        );
      }
      _preset = null;
      _normalizeRange();
    });
    _refreshPreview();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end),
      helpText: tr('সময় নির্বাচন করুন', 'Select a time'),
    );
    if (!mounted || picked == null) return;

    setState(() {
      final boundary = isStart ? _start : _end;
      final updated = DateTime(
        boundary.year,
        boundary.month,
        boundary.day,
        picked.hour,
        picked.minute,
        0,
      );
      if (isStart) {
        _start = updated;
      } else {
        _end = updated;
      }
      _preset = null;
      _normalizeRange();
    });
    _refreshPreview();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _refreshPreview() async {
    if (widget.academyId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _previewError = tr(
          'একাডেমি আইডি পাওয়া যায়নি।',
          'Academy ID was not found.',
        );
        _isLoadingPreview = false;
      });
      return;
    }

    final requestedStart = _start;
    final requestedEnd = _end;
    setState(() {
      _isLoadingPreview = true;
      _previewError = null;
    });

    try {
      final data = await FinancialReportService.fetchReport(
        academyId: widget.academyId,
        start: requestedStart,
        end: requestedEnd,
      );
      if (!mounted || requestedStart != _start || requestedEnd != _end) return;
      setState(() {
        _report = data;
        _isLoadingPreview = false;
      });
    } catch (e) {
      if (!mounted || requestedStart != _start || requestedEnd != _end) return;
      setState(() {
        _report = null;
        _previewError = e.toString();
        _isLoadingPreview = false;
      });
    }
  }

  Future<void> _loadSaved() async {
    setState(() {
      _isLoadingSaved = true;
      _savedError = null;
    });
    try {
      final records = await FinancialReportService.loadSaved(
        academyId: widget.academyId,
      );
      if (!mounted) return;
      setState(() {
        _saved = records;
        _isLoadingSaved = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savedError = e.toString();
        _isLoadingSaved = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PDF actions
  // ---------------------------------------------------------------------------

  Future<void> _generate({bool previewOnly = false}) async {
    final report = _report;
    if (report == null || report.transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'এই সময়সীমায় কোনো লেনদেন নেই।',
              'No transactions in this range.',
            ),
          ),
          backgroundColor: AppTheme.warningOf(context),
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final bytes = await FinancialReportService.buildPdf(
        report: report,
        academyId: widget.academyId,
      );
      if (!mounted) return;

      if (previewOnly) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name:
              'financial_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
        );
      } else {
        final record = await FinancialReportService.savePdf(
          academyId: widget.academyId,
          bytes: bytes,
          start: report.start,
          end: report.end,
        );
        if (!mounted) return;
        await _loadSaved();
        if (!mounted) return;
        _showSavedSnackBar(record);
      }
      if (!mounted) return;
      setState(() => _lastBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('PDF তৈরি করা যায়নি', 'Could not create the PDF')}: $e',
          ),
          backgroundColor: AppTheme.errorOf(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showSavedSnackBar(SavedFinancialPdf record) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            '${record.fileName} সংরক্ষিত হয়েছে: ${record.filePath}',
            '${record.fileName} saved to: ${record.filePath}',
          ),
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: tr('খুলুন', 'Open'),
          onPressed: () => _openFile(record),
        ),
      ),
    );
  }

  Future<void> _openFile(SavedFinancialPdf record) async {
    try {
      final result = await OpenFilex.open(record.filePath);
      if (!mounted || result.type == ResultType.done) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('ফাইলটি খোলা যায়নি', 'Could not open the file')}: ${result.message}',
          ),
          backgroundColor: AppTheme.warningOf(context),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('ফাইলটি খোলা যায়নি', 'Could not open the file')}: $e',
          ),
          backgroundColor: AppTheme.errorOf(context),
        ),
      );
    }
  }

  Future<void> _shareFile(SavedFinancialPdf record) async {
    try {
      final file = File(record.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('ফাইলটি আর পাওয়া যাচ্ছে না।', 'The file no longer exists.'),
            ),
            backgroundColor: AppTheme.warningOf(context),
          ),
        );
        await _loadSaved();
        return;
      }
      await Printing.sharePdf(
        bytes: await file.readAsBytes(),
        filename: record.fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('শেয়ার করা যায়নি', 'Could not share the file')}: $e',
          ),
          backgroundColor: AppTheme.errorOf(context),
        ),
      );
    }
  }

  Future<void> _confirmDelete(SavedFinancialPdf record) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(tr('PDF মুছুন', 'Delete PDF')),
        content: Text(
          tr(
            '${record.fileName} ফাইলটি স্থায়ীভাবে মুছে ফেলতে চান?',
            'Permanently delete ${record.fileName}?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(tr('বাতিল', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(tr('মুছুন', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FinancialReportService.delete(record);
      if (!mounted) return;
      setState(() {
        _saved.removeWhere((item) => item.id == record.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('PDF মুছে ফেলা হয়েছে।', 'PDF deleted.'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('মুছে ফেলা যায়নি', 'Could not delete')}: $e'),
          backgroundColor: AppTheme.errorOf(context),
        ),
      );
    }
  }

  String _formatSize(int bytes) {
    String text;
    if (bytes < 1024) {
      text = '$bytes B';
    } else if (bytes < 1024 * 1024) {
      text = '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      text = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return _isEnglish ? text : bn(text);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final brand = AppTheme.brandOf(context);

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(tr('আর্থিক রিপোর্ট (PDF)', 'Financial Report (PDF)')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: tr('প্রিভিউ রিফ্রেশ', 'Refresh preview'),
            onPressed: _isLoadingPreview ? null : _refreshPreview,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildReportHeader(brand),
            const SizedBox(height: 18),
            _buildSummarySection(),
            const SizedBox(height: 14),
            _buildGenerateBar(brand),
            const SizedBox(height: 22),
            _buildSavedSection(brand),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHeader(Color brand) {
    final presets = <(String key, String label, String english)>[
      ('today', 'আজ', 'Today'),
      ('7days', 'গত ৭ দিন', 'Last 7 Days'),
      ('month', 'এই মাস', 'This Month'),
      ('year', 'এই বছর', 'This Year'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            brand.withValues(alpha: 0.20),
            brand.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.tileOf(context, brand),
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: brand,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'আর্থিক হিসাব',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.tileOf(context, brand),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        FinancialReportService.formatRange(
                          _start,
                          _end,
                          english: _isEnglish,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.tileInkOf(context, brand),
                          fontWeight: FontWeight.w700,
                          fontFeatures: AppTheme.numericFeatures,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _sectionTitle(
            Icons.date_range,
            tr('সময়সীমা নির্বাচন করুন', 'Select date & time range'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final preset in presets)
                ChoiceChip(
                  label: Text(_isEnglish ? preset.$3 : preset.$2),
                  selected: _preset == preset.$1,
                  onSelected: (_) => _applyPreset(preset.$1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _rangeTile(isStart: true, brand: brand)),
              const SizedBox(width: 10),
              Expanded(child: _rangeTile(isStart: false, brand: brand)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'শুরু ও শেষের তারিখ/সময় বদলালে সারাংশ স্বয়ংক্রিয়ভাবে আপডেট হয়।',
              'The summary updates automatically when you change the range.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppTheme.brandOf(context)),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _rangeTile({required bool isStart, required Color brand}) {
    final value = isStart ? _start : _end;
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    );

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, brand),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isStart ? tr('শুরু', 'Start') : tr('শেষ', 'End'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Text(
            FinancialReportService.formatDateTime(value, english: _isEnglish),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: () => _pickDate(isStart: isStart),
                  icon: const Icon(Icons.calendar_month_outlined, size: 14),
                  label: Text(tr('তারিখ', 'Date')),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: () => _pickTime(isStart: isStart),
                  icon: const Icon(Icons.access_time, size: 14),
                  label: Text(tr('সময়', 'Time')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.insights_outlined,
          tr('সারাংশ (প্রিভিউ)', 'Summary preview'),
        ),
        const SizedBox(height: 10),
        if (_isLoadingPreview)
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: AppLoadingState(),
            ),
          )
        else if (_previewError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AppErrorState(
                message: _previewError!,
                onRetry: _refreshPreview,
              ),
            ),
          )
        else if (_report == null || _report!.transactions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppEmptyState(
                icon: Icons.receipt_long_outlined,
                message: tr(
                  'এই সময়সীমায় কোনো আয়/ব্যয়ের এন্ট্রি পাওয়া যায়নি।',
                  'No income or expense entries found in this range.',
                ),
                actionLabel: tr('রিফ্রেশ', 'Refresh'),
                onAction: _refreshPreview,
              ),
            ),
          )
        else
          _summaryGrid(_report!),
      ],
    );
  }

  Widget _summaryGrid(FinancialReportData report) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _metricCard(
                title: tr('আয় ও ব্যালেন্স', 'Income & balance'),
                metrics: [
                  _SummaryMetric(
                    label: tr('মোট আয়', 'Total income'),
                    value: FinancialReportService.money(
                      report.totalIncome,
                      english: _isEnglish,
                    ),
                    icon: Icons.arrow_downward_rounded,
                    color: AppTheme.successOf(context),
                  ),
                  _SummaryMetric(
                    label: tr('নিট ব্যালেন্স', 'Net balance'),
                    value: FinancialReportService.money(
                      report.netBalance,
                      english: _isEnglish,
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppTheme.infoOf(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                title: tr('ব্যয় ও এন্ট্রি', 'Expense & entries'),
                metrics: [
                  _SummaryMetric(
                    label: tr('মোট ব্যয়', 'Total expense'),
                    value: FinancialReportService.money(
                      report.totalExpense,
                      english: _isEnglish,
                    ),
                    icon: Icons.arrow_upward_rounded,
                    color: AppTheme.errorOf(context),
                  ),
                  _SummaryMetric(
                    label: tr('মোট এন্ট্রি', 'Entry count'),
                    value: _isEnglish
                        ? '${report.entryCount}'
                        : bn(report.entryCount),
                    icon: Icons.confirmation_number_outlined,
                    color: AppTheme.brandOf(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _recentEntries(report),
      ],
    );
  }

  /// Two cards, each holding two metrics. Values wrap instead of being
  /// ellipsised, so long amounts are never clipped on narrow screens.
  Widget _metricCard({
    required String title,
    required List<_SummaryMetric> metrics,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          for (final metric in metrics) ...[
            _metricRow(metric),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(_SummaryMetric metric) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(metric.icon, size: 14, color: metric.color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                metric.label,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          metric.value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppTheme.tileInkOf(context, metric.color),
            fontFeatures: AppTheme.numericFeatures,
          ),
          softWrap: true,
        ),
      ],
    );
  }

  Widget _recentEntries(FinancialReportData report) {
    final recent = report.transactions.take(4).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('সাম্প্রতিক এন্ট্রি', 'Recent entries'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final item in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      item.isIncome
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      size: 16,
                      color: item.isIncome
                          ? AppTheme.successOf(context)
                          : AppTheme.errorOf(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.category,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${item.isIncome ? '+' : '-'}${FinancialReportService.money(item.amount, english: _isEnglish)}',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: item.isIncome
                            ? AppTheme.successOf(context)
                            : AppTheme.errorOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            if (report.entryCount > recent.length)
              Text(
                tr(
                  'আরও ${bn(report.entryCount - recent.length)}টি এন্ট্রি PDF-এ থাকবে।',
                  '${report.entryCount - recent.length} more entries are in the PDF.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateBar(Color brand) {
    final canGenerate =
        _report != null && _report!.transactions.isNotEmpty && !_isGenerating;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: canGenerate ? () => _generate() : null,
              icon: _isGenerating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                _isGenerating
                    ? tr('PDF তৈরি হচ্ছে...', 'Generating PDF...')
                    : tr('PDF তৈরি ও সংরক্ষণ করুন', 'Generate & save PDF'),
              ),
            ),
            if (_lastBytes != null)
              TextButton.icon(
                onPressed: _isGenerating
                    ? null
                    : () => _generate(previewOnly: true),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(tr('PDF প্রিভিউ / প্রিন্ট', 'Preview / print PDF')),
              ),
            const SizedBox(height: 4),
            Text(
              tr(
                'PDF ডিভাইসের Download/Documents ফোল্ডারে সংরক্ষণ হয় এবং নিচের তালিকায় দেখা যায়।',
                'The PDF is saved in the device Download/Documents folder and appears below.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedSection(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                Icons.folder_open_outlined,
                tr('সংরক্ষিত PDF সমূহ', 'Saved PDFs'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: tr('তালিকা রিফ্রেশ', 'Refresh list'),
              onPressed: _isLoadingSaved ? null : _loadSaved,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingSaved)
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: AppLoadingState(),
            ),
          )
        else if (_savedError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AppErrorState(message: _savedError!, onRetry: _loadSaved),
            ),
          )
        else if (_saved.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppEmptyState(
                icon: Icons.picture_as_pdf_outlined,
                message: tr(
                  'এখনো কোনো PDF সংরক্ষণ করা হয়নি।',
                  'No PDF has been saved yet.',
                ),
              ),
            ),
          )
        else
          Column(
            children: [
              for (final item in _saved) _savedPdfTile(item, brand),
              const SizedBox(height: 4),
              Text(
                tr(
                  'মোট ${bn(_saved.length)}টি ফাইল',
                  '${_saved.length} file(s)',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }

  Widget _savedPdfTile(SavedFinancialPdf item, Color brand) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.tileOf(context, Colors.red),
                  child: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        FinancialReportService.formatRange(
                          item.startAt,
                          item.endAt,
                          english: _isEnglish,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _metaChip(
                  Icons.schedule_outlined,
                  '${tr('তৈরি', 'Created')}: ${FinancialReportService.formatDateTime(item.createdAt, english: _isEnglish)}',
                ),
                _metaChip(Icons.storage_outlined, _formatSize(item.fileSize)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.filePath,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: AppTheme.mutedOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.open_in_new_outlined),
                  tooltip: tr('খুলুন / দেখুন', 'Open / view'),
                  color: brand,
                  onPressed: () => _openFile(item),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: tr('শেয়ার করুন', 'Share'),
                  color: brand,
                  onPressed: () => _shareFile(item),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: tr('মুছুন', 'Delete'),
                  color: AppTheme.errorOf(context),
                  onPressed: () => _confirmDelete(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.mutedOf(context)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
