import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/due_students_report.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/due_students_report_service.dart';
import 'package:academy_management/widgets/async_state_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

/// Dedicated screen for generating the class-wise due-students PDF.
///
/// This screen is only reachable from the AppBar of `TotalDueDetailsView`.
class DueStudentsPdfReportView extends StatefulWidget {
  final String academyId;

  const DueStudentsPdfReportView({super.key, required this.academyId});

  @override
  State<DueStudentsPdfReportView> createState() =>
      _DueStudentsPdfReportViewState();
}

class _DueStudentsPdfReportViewState extends State<DueStudentsPdfReportView> {
  late final AppStateController _appState;
  Worker? _languageWorker;
  bool _isEnglish = false;

  DueStudentsReportData? _report;
  bool _isLoadingReport = true;
  String? _reportError;

  bool _isGenerating = false;
  Uint8List? _lastBytes;

  List<SavedDueStudentsPdf> _saved = [];
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

    _refreshReport();
    _loadSaved();
  }

  @override
  void dispose() {
    _languageWorker?.dispose();
    super.dispose();
  }

  String tr(String bangla, String english) => _isEnglish ? english : bangla;

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _refreshReport() async {
    if (widget.academyId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _reportError = tr(
          'একাডেমি আইডি পাওয়া যায়নি।',
          'Academy ID was not found.',
        );
        _isLoadingReport = false;
      });
      return;
    }

    setState(() {
      _isLoadingReport = true;
      _reportError = null;
    });
    try {
      final data = await DueStudentsReportService.fetchReport(
        academyId: widget.academyId,
      );
      if (!mounted) return;
      setState(() {
        _report = data;
        _isLoadingReport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _reportError = e.toString();
        _isLoadingReport = false;
      });
    }
  }

  Future<void> _loadSaved() async {
    setState(() {
      _isLoadingSaved = true;
      _savedError = null;
    });
    try {
      final records = await DueStudentsReportService.loadSaved(
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
    if (report == null || report.totalStudents == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'এই মুহূর্তে কোনো বকেয়া শিক্ষার্থী নেই।',
              'There are no due students right now.',
            ),
          ),
          backgroundColor: AppTheme.warningOf(context),
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final bytes = await DueStudentsReportService.buildPdf(
        report: report,
        academyId: widget.academyId,
      );
      if (!mounted) return;

      if (previewOnly) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name:
              'due_students_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      } else {
        final record = await DueStudentsReportService.savePdf(
          academyId: widget.academyId,
          bytes: bytes,
          report: report,
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

  void _showSavedSnackBar(SavedDueStudentsPdf record) {
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

  Future<void> _openFile(SavedDueStudentsPdf record) async {
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

  Future<void> _shareFile(SavedDueStudentsPdf record) async {
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

  Future<void> _confirmDelete(SavedDueStudentsPdf record) async {
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
      await DueStudentsReportService.delete(record);
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
        title: Text(tr('বকেয়া শিক্ষার্থীদের রিপোর্ট', 'Due Students Report')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: tr('রিফ্রেশ', 'Refresh'),
            onPressed: _isLoadingReport ? null : _refreshReport,
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
            const SizedBox(height: 18),
            _buildClassSection(brand),
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
    final generatedAt = _report?.generatedAt ?? DateTime.now();
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
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppTheme.tileOf(context, Colors.redAccent),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.redAccent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('বকেয়া শিক্ষার্থীদের রিপোর্ট', 'Due Students Report'),
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
                    '${tr('তৈরি', 'Generated')}: ${DueStudentsReportService.formatDateTime(generatedAt, english: _isEnglish)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.tileInkOf(context, brand),
                      fontWeight: FontWeight.w700,
                      fontFeatures: AppTheme.numericFeatures,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'চলতি বছরের প্রতি মাসের ফি পরিশোধের অবস্থা শ্রেণি অনুযায়ী দেখানো হয়।',
                    'Monthly fee payment status for the current year is shown class by class.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
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
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
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
        if (_isLoadingReport)
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: AppLoadingState(),
            ),
          )
        else if (_reportError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AppErrorState(
                message: _reportError!,
                onRetry: _refreshReport,
              ),
            ),
          )
        else if (_report == null || _report!.totalStudents == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppEmptyState(
                icon: Icons.school_outlined,
                message: tr(
                  'চলতি বছরে কোনো বকেয়া শিক্ষার্থী পাওয়া যায়নি।',
                  'No due students found for the current year.',
                ),
                actionLabel: tr('রিফ্রেশ', 'Refresh'),
                onAction: _refreshReport,
              ),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _metricCard(
                  title: tr('শিক্ষার্থী ও বকেয়া', 'Students & dues'),
                  metrics: [
                    (
                      label: tr('মোট বকেয়া শিক্ষার্থী', 'Total due students'),
                      value:
                          '${bn(_report!.totalStudents)} ${tr('জন', 'students')}',
                      icon: Icons.groups_outlined,
                      color: AppTheme.errorOf(context),
                    ),
                    (
                      label: tr('মোট বকেয়া', 'Total due'),
                      value: DueStudentsReportService.money(
                        _report!.totalDueAmount,
                        english: _isEnglish,
                      ),
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppTheme.warningOf(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  title: tr('ক্লাস ও মাস', 'Classes & months'),
                  metrics: [
                    (
                      label: tr('ক্লাস সংখ্যা', 'Class count'),
                      value: bn(_report!.totalClasses),
                      icon: Icons.class_outlined,
                      color: AppTheme.brandOf(context),
                    ),
                    (
                      label: tr('মোট বকেয়া মাস', 'Total pending months'),
                      value: bn(_report!.totalPendingMonths),
                      icon: Icons.calendar_month_outlined,
                      color: AppTheme.infoOf(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required List<({String label, String value, IconData icon, Color color})>
    metrics,
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
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildClassSection(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.format_list_bulleted_outlined,
          tr('শ্রেণি অনুযায়ী বিবরণ', 'Class-wise breakdown'),
        ),
        const SizedBox(height: 10),
        if (_isLoadingReport)
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: AppLoadingState(),
            ),
          )
        else if (_reportError != null ||
            _report == null ||
            _report!.classes.isEmpty)
          const SizedBox.shrink()
        else
          ..._report!.classes.map((group) => _classTile(group, brand)),
      ],
    );
  }

  Widget _classTile(DueClassGroup group, Color brand) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.tileOf(context, brand),
          child: Icon(Icons.class_outlined, color: brand, size: 20),
        ),
        title: Text(
          group.className,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${tr('শিক্ষার্থী', 'Students')}: ${bn(group.studentCount)} · ${DueStudentsReportService.money(group.dueAmount, english: _isEnglish)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${tr('বকেয়া মাস', 'Pending months')}: ${group.pendingMonths.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.errorOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final student in group.students) _studentRow(student),
        ],
      ),
    );
  }

  Widget _studentRow(DueStudentRecord student) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tr('রোল', 'Roll')}: ${student.roll} · ${tr('বাবার নাম', 'Father')}: ${student.fatherName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${tr('মাস', 'Months')}: ${student.pendingMonths.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DueStudentsReportService.money(
              student.dueAmount,
              english: _isEnglish,
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.errorOf(context),
              fontWeight: FontWeight.w700,
              fontFeatures: AppTheme.numericFeatures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateBar(Color brand) {
    final canGenerate =
        _report != null && _report!.totalStudents > 0 && !_isGenerating;

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

  Widget _savedPdfTile(SavedDueStudentsPdf item, Color brand) {
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
                        '${tr('শিক্ষার্থী', 'Students')}: ${bn(item.studentCount)} · ${tr('ক্লাস', 'Classes')}: ${bn(item.classCount)}',
                        style: Theme.of(context).textTheme.bodySmall,
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
                  '${tr('তৈরি', 'Created')}: ${DueStudentsReportService.formatDateTime(item.createdAt, english: _isEnglish)}',
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
