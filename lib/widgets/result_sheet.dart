import 'dart:typed_data';

import 'package:academy_management/services/result_calculator.dart';
import 'package:flutter/material.dart';

/// Immutable input for the result sheet. All images are pre-fetched bytes so
/// the same widget renders identically in-app and in the captured PDF.
class ResultSheetData {
  final Map<String, dynamic> academy;
  final Map<String, dynamic> student;
  final String examTitle;
  final String className;
  final Map<String, dynamic> resultData;
  final Map<String, dynamic> fullMarksData;
  final List<Map<String, dynamic>> peers;
  final Uint8List? logoBytes;
  final Uint8List? photoBytes;
  final String? photoUrl;
  final Uint8List? signatureBytes;
  final String generatedAt;

  const ResultSheetData({
    required this.academy,
    required this.student,
    required this.examTitle,
    required this.className,
    required this.resultData,
    required this.fullMarksData,
    required this.peers,
    this.logoBytes,
    this.photoBytes,
    this.photoUrl,
    this.signatureBytes,
    required this.generatedAt,
  });
}

/// A4-proportioned result sheet used for the in-app preview AND for the
/// screenshot that is embedded into printed / downloaded PDFs.
class ResultSheet extends StatelessWidget {
  /// Logical A4 size at 96dpi.
  static const double sheetWidth = 794;
  static const double sheetHeight = 1123;

  /// Official document font of this project — the bundled Bengali TTF also
  /// used by the report/routine/certificate PDF generators.
  static const String documentFont = 'Ekush';

  final ResultSheetData data;

  const ResultSheet({super.key, required this.data});

  static const _navy = Color(0xFF1B365D);
  static const _teal = Color(0xFF0F766E);
  static const _ink = Color(0xFF1F2937);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFCBD5E1);
  static const _soft = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final subjects = ResultCalculator.subjects(data.resultData).toList();
    final obtained = ResultCalculator.obtainedMarks(data.resultData);
    final full = ResultCalculator.fullMarks(
      data.resultData,
      data.fullMarksData,
    );
    final percent = ResultCalculator.percentage(
      data.resultData,
      data.fullMarksData,
    );
    final gpa = ResultCalculator.gpa(data.resultData, data.fullMarksData);
    final grade = ResultCalculator.overallGrade(
      data.resultData,
      data.fullMarksData,
      overallPercent: percent.value * 100,
    );
    final roll = data.student['roll']?.toString() ?? '-';
    final position = ResultCalculator.rollRank(data.peers, roll);

    return Container(
      width: sheetWidth,
      height: sheetHeight,
      color: Colors.white,
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 12),
          _titleBand(percent.label),
          const SizedBox(height: 12),
          _middleBlock(position, grade),
          const SizedBox(height: 12),
          _marksTable(subjects, position),
          const Spacer(),
          _summaryStrip(obtained, full, percent.label, gpa, grade, position),
          const SizedBox(height: 12),
          _footer(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header: logo + institution info (left), student photo (right)
  // ---------------------------------------------------------------------------
  Widget _header() {
    final academy = data.academy;
    final name = academy['academy_name']?.toString() ?? 'Academy';
    final address = academy['address']?.toString() ?? '';
    final phone = academy['phone']?.toString() ?? '';
    final email =
        (academy['admin_email'] ?? academy['email'])?.toString() ?? '';
    final eiin = academy['eiin']?.toString() ?? '';
    final code = academy['academy_code']?.toString() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: data.logoBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.memory(
                    data.logoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.school_outlined,
                      size: 34,
                      color: _muted,
                    ),
                  ),
                )
              : const Icon(Icons.school_outlined, size: 34, color: _muted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontFamily: documentFont,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  address,
                  style: _style(size: 11, color: _muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Plain text only below the academy name — no boxes or pills.
              if (phone.isNotEmpty || email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (phone.isNotEmpty) 'Phone: $phone',
                      if (email.isNotEmpty) 'Email: $email',
                    ].join('   •   '),
                    style: _style(size: 10, color: _muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (eiin.isNotEmpty || code.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    [
                      if (eiin.isNotEmpty) 'EIIN: $eiin',
                      if (code.isNotEmpty) 'Code: $code',
                    ].join('   •   '),
                    style: _style(size: 10, color: _muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 78,
          height: 92,
          decoration: BoxDecoration(
            border: Border.all(color: _navy, width: 1.5),
            borderRadius: BorderRadius.circular(6),
            color: _soft,
          ),
          child: data.photoBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    data.photoBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _photoFallback(),
                  ),
                )
              : data.photoUrl != null && data.photoUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        data.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _photoFallback(),
                      ),
                    )
                  : _photoFallback(),
        ),
      ],
    );
  }

  Widget _photoFallback() => const Center(
    child: Icon(Icons.person_outline, size: 44, color: _muted),
  );

  // ---------------------------------------------------------------------------
  // Title band
  // ---------------------------------------------------------------------------
  Widget _titleBand(String percentLabel) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
    decoration: BoxDecoration(
      color: _navy,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ফলাফল পত্র  |  RESULT SHEET',
              style: _style(
                size: 16,
                bold: true,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${data.examTitle}  •  শ্রেণী: ${data.className}',
              style: _style(size: 11, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            percentLabel,
            style: _style(size: 15, bold: true, color: _navy),
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // Middle split: student info (left) + grading scale (right)
  // ---------------------------------------------------------------------------
  Widget _middleBlock(String position, ResultGrade grade) {
    final boxDecoration = BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(8),
    );

    // Equal height: IntrinsicHeight + stretch keeps both boxes perfectly
    // aligned without leaving an empty gap under either side.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: boxDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(
                    'নাম / Name',
                    data.student['name']?.toString() ??
                        data.student['full_name']?.toString() ??
                        '-',
                  ),
                  _infoRow(
                    'রোল / Roll',
                    data.student['roll']?.toString() ?? '-',
                  ),
                  _infoRow('শ্রেণী / Class', data.className),
                  _infoRow('পরীক্ষা / Exam', data.examTitle),
                  _infoRow(
                    'পিতার নাম / Father',
                    data.student['father_name']?.toString() ?? '-',
                  ),
                  _infoRow('মেরিট / Position', position),
                  _infoRow(
                    'ফলাফল / Result',
                    '${grade.remark} (${grade.label})',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: boxDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final band in ResultCalculator.gradeScale)
                    _scaleRow(band),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: _style(size: 11.5, bold: true, color: _navy),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text('$label:', style: _style(size: 10, color: _muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: _style(size: 10.5, bold: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _scaleRow(ResultGrade band) => Container(
    padding: const EdgeInsets.symmetric(vertical: 3),
    decoration: BoxDecoration(
      color: ResultCalculator.gradeScale.indexOf(band).isEven
          ? Colors.white
          : _soft,
    ),
    child: Row(
      children: [
        SizedBox(width: 42, child: _CenterText(band.label, bold: true)),
        SizedBox(width: 72, child: _CenterText(band.range, size: 9)),
        SizedBox(width: 38, child: _CenterText(band.point.toStringAsFixed(2), size: 9)),
        Expanded(
          child: _CenterText(
            band.remark,
            size: 9,
            color: band.label == 'F' ? Colors.red : _ink,
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // Marks table
  // ---------------------------------------------------------------------------
  Widget _marksTable(List<String> subjects, String position) {
    final rowHeight = subjects.isEmpty
        ? 32.0
        : (300 / subjects.length).clamp(26.0, 32.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('বিষয়ভিত্তিক ফলাফল  •  Subject-wise Marks'),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: _line, width: 0.8),
          columnWidths: const {
            0: FlexColumnWidth(2.6),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
            5: FlexColumnWidth(1.1),
            6: FlexColumnWidth(1.1),
            7: FlexColumnWidth(0.9),
            8: FlexColumnWidth(1.1),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _navy),
              children: const [
                _Cell('বিষয় / Subject', header: true),
                _Cell('CQ', header: true),
                _Cell('MCQ', header: true),
                _Cell('ভিভা', header: true),
                _Cell('প্র্যাক', header: true),
                _Cell('মোট', header: true),
                _Cell('ফুল', header: true),
                _Cell('গ্রেড', header: true),
                _Cell('Pos', header: true),
              ],
            ),
            ...subjects.map((subject) {
              final cq = ResultCalculator.mark(data.resultData, subject, 'cq');
              final mcq = ResultCalculator.mark(data.resultData, subject, 'mcq');
              final viva = ResultCalculator.mark(data.resultData, subject, 'viva');
              final practical =
                  ResultCalculator.mark(data.resultData, subject, 'practical');
              final total = cq + mcq + viva + practical;
              final fullMark =
                  ResultCalculator.subjectFullMark(data.fullMarksData, subject);
              final subPercent = fullMark > 0 ? (total / fullMark) * 100 : 0.0;
              final subGrade = ResultCalculator.gradeFor(
                subPercent.clamp(0.0, 100.0),
              );
              final subPos = ResultCalculator.subjectRank(
                data.peers,
                subject,
                total,
              );
              return TableRow(
                decoration: BoxDecoration(
                  color: subjects.indexOf(subject).isEven ? Colors.white : _soft,
                ),
                children: [
                  _Cell(subject, bold: true, height: rowHeight),
                  _Cell(_fmt(cq), height: rowHeight),
                  _Cell(_fmt(mcq), height: rowHeight),
                  _Cell(_fmt(viva), height: rowHeight),
                  _Cell(_fmt(practical), height: rowHeight),
                  _Cell(_fmt(total), bold: true, height: rowHeight),
                  _Cell(_fmt(fullMark), height: rowHeight),
                  _Cell(subGrade.label, bold: true, accent: true, height: rowHeight),
                  _Cell(subPos, height: rowHeight),
                ],
              );
            }),
            if (subjects.isEmpty)
              TableRow(
                children: [
                  TableCell(
                    child: SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          'এই পরীক্ষার নম্বর এন্ট্রি করা হয়নি  •  No marks entered',
                          style: _style(size: 10, color: _muted),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Summary + footer
  // ---------------------------------------------------------------------------
  Widget _summaryStrip(
    double obtained,
    double full,
    String percentLabel,
    double gpa,
    ResultGrade grade,
    String position,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _soft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _summaryItem('মোট নম্বর', '${_fmt(obtained)} / ${_fmt(full)}'),
            _summaryItem('শতাংশ', percentLabel),
            _summaryItem('GPA', gpa.toStringAsFixed(2)),
            _summaryItem('গ্রেড', grade.label),
            _summaryItem('মেরিট', position),
          ],
        ),
      );

  Widget _summaryItem(String label, String value) => Column(
    children: [
      Text(label, style: _style(size: 9.5, color: _muted)),
      const SizedBox(height: 2),
      Text(value, style: _style(size: 13, bold: true, color: _navy)),
    ],
  );

  Widget _footer() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'তারিখ / Date: ${data.generatedAt}',
            style: _style(size: 9.5, color: _muted),
          ),
          const SizedBox(height: 2),
          Text(
            'একাডেমি ম্যানেজমেন্ট সিস্টেম দ্বারা তৈরি',
            style: _style(size: 9, color: _muted),
          ),
        ],
      ),
      Column(
        children: [
          SizedBox(
            height: 46,
            width: 120,
            child: data.signatureBytes != null
                ? Image.memory(
                    data.signatureBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
          Container(width: 170, height: 1, color: _navy),
          const SizedBox(height: 4),
          Text(
            'প্রধান শিক্ষক / Head of Institution',
            style: _style(size: 10, bold: true),
          ),
        ],
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------
  static TextStyle _style({
    double size = 11,
    bool bold = false,
    Color color = _ink,
  }) {
    return TextStyle(
      fontFamily: documentFont,
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      height: 1.35,
      // Tabular figures keep digits aligned and stop them colliding.
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static String _fmt(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

class _CenterText extends StatelessWidget {
  final String text;
  final bool bold;
  final double size;
  final Color color;
  const _CenterText(
    this.text, {
    this.bold = false,
    this.size = 10,
    this.color = const Color(0xFF1F2937),
  });

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ResultSheet._style(
      size: size,
      bold: bold,
      color: color,
    ),
  );
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;
  final bool bold;
  final bool accent;
  final double height;
  const _Cell(
    this.text, {
    this.header = false,
    this.bold = false,
    this.accent = false,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context) => TableCell(
    verticalAlignment: TableCellVerticalAlignment.middle,
    child: SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ResultSheet._style(
              size: header ? 9 : 10,
              bold: header || bold,
              color: header
                  ? Colors.white
                  : accent
                      ? ResultSheet._teal
                      : ResultSheet._ink,
            ),
          ),
        ),
      ),
    ),
  );
}
