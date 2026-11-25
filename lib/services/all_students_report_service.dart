import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/models/academy.dart';
import 'package:academy_management/models/all_students_report.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/financial_report_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches, groups, renders and stores the complete all-students PDF.
///
/// The PDF deliberately uses the exact HTML/CSS pipeline from
/// [FinancialReportService] (and `DueStudentsReportService`): a real Bengali
/// TTF embedded as a base64 data URI, then the native WebView converter with a
/// `printing` fallback. Student information is printed in compact cards; only
/// the fields explicitly excluded below are hidden from the document.
abstract final class AllStudentsReportService {
  static const List<String> _fontAssets = [
    'assets/fonts/HindSiliguri-Regular.ttf',
    'assets/fonts/Ekush-Regular.ttf',
  ];
  static const String _logoAsset = 'assets/images/institute_logo.png';
  static const String _prefsKey = 'all_students_pdf_reports_v1';

  /// Admission/issue date aliases, preferred in this order for the PDF's
  /// "ভর্তির তারিখ" row. `created_at` is the issue date on student rows.
  static const List<String> _admissionDateKeys = [
    'created_at',
    'admission_date',
    'admitted_at',
    'issue_date',
    'issued_at',
    'admission',
  ];

  // ---------------------------------------------------------------------------
  // Public formatting helpers (mirror the financial report API).
  // ---------------------------------------------------------------------------

  static String formatDateTime(DateTime value, {required bool english}) =>
      FinancialReportService.formatDateTime(value, english: english);

  static String money(double value, {required bool english}) =>
      FinancialReportService.money(value, english: english);

  // ---------------------------------------------------------------------------
  // Data loading and grouping
  // ---------------------------------------------------------------------------

  static String _toAsciiDigits(String value) {
    const bengaliDigits = '০১২৩৪৫৬৭৮৯';
    return value.replaceAllMapped(RegExp(r'[০-৯]'), (match) {
      final index = bengaliDigits.indexOf(match.group(0)!);
      return index < 0 ? match.group(0)! : index.toString();
    });
  }

  static double _amount(dynamic value) {
    final text = _toAsciiDigits(
      value?.toString() ?? '',
    ).replaceAll(',', '').trim();
    return double.tryParse(text) ?? 0.0;
  }

  static String _text(
    Map<String, dynamic> row,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static int _rollOrder(String roll) =>
      int.tryParse(_toAsciiDigits(roll)) ?? 999999;

  static int _compareStudents(AllStudentRecord a, AllStudentRecord b) {
    final aRoll = _rollOrder(a.roll);
    final bRoll = _rollOrder(b.roll);
    if (aRoll != bRoll) return aRoll.compareTo(bRoll);
    return a.name.compareTo(b.name);
  }

  /// Reads every student of the academy. `select('*')` is intentional: the
  /// students table has no schema migration in this repo, so naming explicit
  /// columns could trigger a missing-column error on some installations.
  static Future<AllStudentsReportData> fetchReport({
    required String academyId,
  }) async {
    final response = await Supabase.instance.client
        .from('students')
        .select('*')
        .eq('academy_id', academyId);
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final grouped = <String, List<AllStudentRecord>>{};
    for (final row in rows) {
      final className = _text(row, const [
        'class',
        'class_name',
      ], 'অন্যান্য ক্লাস');
      final student = AllStudentRecord(
        raw: row,
        studentId: _text(row, const ['id', 'student_id'], ''),
        name: _text(row, const ['full_name', 'name'], 'নামহীন শিক্ষার্থী'),
        roll: _text(row, const ['roll', 'roll_no'], 'নেই'),
        className: className,
      );
      grouped.putIfAbsent(className, () => <AllStudentRecord>[]).add(student);
    }

    final classes = grouped.entries.map((entry) {
      final students = entry.value.toList()..sort(_compareStudents);
      return AllStudentClassGroup(className: entry.key, students: students);
    }).toList()..sort((a, b) => a.className.compareTo(b.className));

    return AllStudentsReportData(generatedAt: DateTime.now(), classes: classes);
  }

  // ---------------------------------------------------------------------------
  // PDF rendering (HTML + CSS) — same rendering mechanism as the financial PDF
  // ---------------------------------------------------------------------------

  static Future<String> _loadFontBase64() async {
    for (final asset in _fontAssets) {
      try {
        final data = await rootBundle.load(asset);
        return base64Encode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (_) {
        // Try the next bundled Bengali font.
      }
    }
    return '';
  }

  static String _escape(Object? value) =>
      const HtmlEscape().convert(value?.toString() ?? '');

  static String _imageMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    final head = String.fromCharCodes(
      bytes.take(bytes.length < 256 ? bytes.length : 256),
    ).toLowerCase();
    if (head.contains('<svg')) return 'image/svg+xml';
    return 'image/png';
  }

  static Future<String?> _loadLogoDataUri(Academy? academy) async {
    Uint8List? bytes;
    try {
      final data = await rootBundle.load(_logoAsset);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      bytes = null;
    }

    final remoteUrl = academy?.logoUrl?.trim() ?? '';
    if (remoteUrl.isNotEmpty) {
      try {
        final response = await Dio().get<List<int>>(
          remoteUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final downloaded = response.data;
        if (downloaded != null && downloaded.isNotEmpty) {
          bytes = Uint8List.fromList(downloaded);
        }
      } catch (_) {
        // Keep the bundled logo when the remote one cannot be downloaded.
      }
    }

    if (bytes == null || bytes.isEmpty) return null;
    return 'data:${_imageMimeType(bytes)};base64,${base64Encode(bytes)}';
  }

  /// Download and inline a student's photo so the PDF never depends on the
  /// network at print time. A missing/broken URL simply leaves an empty slot.
  static Future<String?> _loadStudentPhoto(Map<String, dynamic> row) async {
    final url = _text(row, const ['image_url', 'photo_url'], '');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return null;
    }
    try {
      final response = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final typed = Uint8List.fromList(bytes);
      return 'data:${_imageMimeType(typed)};base64,${base64Encode(typed)}';
    } catch (e) {
      debugPrint('All students report: student photo skipped: $e');
      return null;
    }
  }

  static String _admissionText(Map<String, dynamic> row) {
    for (final key in _admissionDateKeys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Date-only Bangla formatting keeps the admission row clean and short.
  static String _formatAdmissionDate(String value) {
    if (value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return bn(value);
    final local = parsed.toLocal();
    return '${bn(local.day)} ${FinancialReportService.banglaMonths[local.month - 1]} ${bn(local.year)}';
  }

  static String _studentCardHtml(
    int index,
    AllStudentRecord student,
    String? photoDataUri,
  ) {
    final guardian = _text(student.raw, const [
      'father_name',
      'guardian_name',
    ], '—');
    final roll = _text(student.raw, const ['roll', 'roll_no'], '—');
    final address = _text(student.raw, const ['address'], '—');
    final fee = money(_amount(student.raw['monthly_fee']), english: false);
    final phone = _text(student.raw, const ['phone', 'mobile'], '—');
    final admission = _formatAdmissionDate(_admissionText(student.raw));
    final photoHtml = photoDataUri == null
        ? '<span class="student-photo"></span>'
        : '<span class="student-photo"><img src="$photoDataUri" alt="" /></span>';

    return '''
      <article class="student-card">
        <div class="student-head">
          <span class="student-index">${bn(index)}</span>
          <span class="student-name">${_escape(student.name)}</span>
          $photoHtml
        </div>
        <table class="fields">
          <colgroup>
            <col style="width: 17%" /><col style="width: 33%" />
            <col style="width: 17%" /><col style="width: 33%" />
          </colgroup>
          <tbody>
            <tr>
              <th>পিতার নাম</th><td class="single-line">${_escape(bn(guardian))}</td>
              <th>রোল</th><td>${_escape(bn(roll))}</td>
            </tr>
            <tr>
              <th>ঠিকানা</th><td>${_escape(bn(address))}</td>
              <th>মাসিক ফি</th><td>${_escape(fee)}</td>
            </tr>
            <tr>
              <th>মোবাইল</th><td>${_escape(bn(phone))}</td>
              <th>ভর্তির তারিখ</th><td>${_escape(admission)}</td>
            </tr>
          </tbody>
        </table>
      </article>
    ''';
  }

  static Future<String> _buildHtml({
    required AllStudentsReportData report,
    required String academyName,
    required String address,
    required String phone,
    required String fontBase64,
    required String? logoDataUri,
  }) async {
    final fontFace = fontBase64.isEmpty
        ? ''
        : '''
      @font-face {
        font-family: 'HindSiliguriPdf';
        src: url('data:font/ttf;base64,$fontBase64') format('truetype');
        font-style: normal;
        font-weight: 400 700;
      }
    ''';
    final logoHtml = logoDataUri == null
        ? ''
        : '<img src="$logoDataUri" alt="লোগো" />';
    final addressHtml = address.isEmpty
        ? ''
        : '<div class="academy-meta">${_escape(address)}</div>';
    final phoneHtml = phone.isEmpty
        ? ''
        : '<div class="academy-meta">ফোন: ${_escape(phone)}</div>';

    final classSections = StringBuffer();
    var serial = 0;
    for (final group in report.classes) {
      final cards = StringBuffer();
      final photos = await Future.wait(
        group.students.map((student) => _loadStudentPhoto(student.raw)),
      );
      for (var i = 0; i < group.students.length; i++) {
        serial++;
        cards.writeln(_studentCardHtml(serial, group.students[i], photos[i]));
      }
      classSections.writeln('''
        <section class="class-block">
          <h2 class="class-title">
            ${_escape(group.className)}
            <span class="class-count">${bn(group.studentCount)} জন</span>
          </h2>
          $cards
        </section>
      ''');
    }
    if (report.classes.isEmpty) {
      classSections.writeln(
        '<div class="empty">এই একাডেমিতে কোনো শিক্ষার্থী পাওয়া যায়নি।</div>',
      );
    }

    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="bn">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8" />')
      ..writeln('<title>সম্পূর্ণ শিক্ষার্থী তালিকা</title>')
      ..writeln('<style>')
      ..writeln(fontFace)
      ..writeln('''
      @page {
        size: A4;
        margin: 13mm 11mm 15mm;
      }
      * { box-sizing: border-box; }
      html, body { margin: 0; padding: 0; }
      body {
        font-family: 'HindSiliguriPdf', 'Noto Sans Bengali', 'Hind Siliguri', sans-serif;
        font-size: 10px;
        line-height: 1.45;
        color: #0f172a;
        text-rendering: optimizeLegibility;
        -webkit-font-smoothing: antialiased;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .report-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 14px;
        padding-bottom: 10px;
        border-bottom: 2px solid #0f766e;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        flex: 1 1 55%;
        min-width: 0;
      }
      .brand img {
        width: 46px;
        height: 46px;
        object-fit: contain;
      }
      .brand-text { min-width: 0; }
      .academy-name {
        font-size: 15px;
        font-weight: 700;
        color: #0f766e;
        overflow-wrap: anywhere;
      }
      .academy-meta {
        margin-top: 2px;
        font-size: 9px;
        color: #64748b;
        overflow-wrap: anywhere;
      }
      .title-block {
        flex: 0 1 45%;
        min-width: 0;
        text-align: right;
      }
      .report-title {
        font-size: 16px;
        font-weight: 700;
        color: #0f172a;
        overflow-wrap: anywhere;
      }
      .header-range {
        margin-top: 3px;
        font-size: 10px;
        font-weight: 600;
        color: #334155;
        overflow-wrap: anywhere;
      }
      .summary-grid {
        display: flex;
        gap: 10px;
        margin-top: 10px;
      }
      .summary-card {
        flex: 1 1 0;
        min-width: 0;
        padding: 10px 12px;
        border: 1px solid #cbd5e1;
        border-radius: 8px;
        background: #f8fafc;
      }
      .metric { min-width: 0; }
      .metric + .metric {
        margin-top: 8px;
        padding-top: 8px;
        border-top: 1px solid #e2e8f0;
      }
      .metric-label {
        display: block;
        font-size: 9px;
        font-weight: 600;
        color: #64748b;
      }
      .metric-value {
        display: block;
        margin-top: 2px;
        font-size: 15px;
        font-weight: 700;
        line-height: 1.25;
        overflow-wrap: anywhere;
        word-break: break-word;
      }
      .students { color: #0f766e; }
      .classes { color: #1d4ed8; }
      .class-block { margin-top: 14px; break-inside: auto; }
      .class-title {
        margin: 0 0 5px;
        padding: 6px 8px;
        border-radius: 6px;
        background: #ccfbf1;
        color: #115e59;
        font-size: 12px;
        font-weight: 700;
        overflow-wrap: anywhere;
      }
      .class-count { margin-left: 8px; font-size: 10px; color: #475569; }
      .student-card {
        margin-bottom: 7px;
        border: 1px solid #cbd5e1;
        border-radius: 6px;
        overflow: hidden;
        break-inside: avoid;
        page-break-inside: avoid;
      }
      .student-head {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 8px;
        background: #f0fdfa;
        border-bottom: 1px solid #cbd5e1;
      }
      .student-index {
        flex: 0 0 26px;
        width: 26px;
        height: 26px;
        border-radius: 50%;
        background: #0f766e;
        color: #ffffff;
        font-size: 10px;
        font-weight: 700;
        text-align: center;
        line-height: 26px;
      }
      .student-name {
        flex: 1 1 auto;
        min-width: 0;
        font-size: 11px;
        font-weight: 700;
        color: #0f172a;
        overflow-wrap: anywhere;
        word-break: break-word;
      }
      .student-photo {
        flex: 0 0 34px;
        width: 34px;
        height: 34px;
        margin-left: auto;
        border: 1px solid #cbd5e1;
        border-radius: 4px;
        background: #f1f5f9;
        overflow: hidden;
      }
      .student-photo img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .fields {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      .fields th,
      .fields td {
        padding: 4px 6px;
        border-bottom: 1px solid #e2e8f0;
        text-align: left;
        vertical-align: top;
        font-size: 9px;
        overflow-wrap: anywhere;
        word-break: break-word;
      }
      .fields th {
        background: #f8fafc;
        color: #475569;
        font-weight: 600;
      }
      .fields td { color: #0f172a; }
      .fields td.single-line {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .empty {
        margin-top: 14px;
        padding: 10px;
        border-radius: 6px;
        background: #f8fafc;
        color: #64748b;
      }
      .generated {
        margin-top: 14px;
        font-size: 8.5px;
        color: #64748b;
        text-align: right;
      }
      ''')
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('<header class="report-header">')
      ..writeln('<div class="brand">')
      ..writeln(logoHtml)
      ..writeln('<div class="brand-text">')
      ..writeln('<div class="academy-name">${_escape(academyName)}</div>')
      ..writeln(addressHtml)
      ..writeln(phoneHtml)
      ..writeln('</div>')
      ..writeln('</div>')
      ..writeln('<div class="title-block">')
      ..writeln('<div class="report-title">সম্পূর্ণ শিক্ষার্থী তালিকা</div>')
      ..writeln(
        '<div class="header-range">তৈরি: ${_escape(formatDateTime(report.generatedAt, english: false))}</div>',
      )
      ..writeln('</div>')
      ..writeln('</header>')
      ..writeln('<section class="summary-grid">')
      ..writeln('''
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">মোট শিক্ষার্থী</span>
            <span class="metric-value students">${bn(report.totalStudents)} জন</span>
          </div>
        </article>
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">ক্লাস সংখ্যা</span>
            <span class="metric-value classes">${bn(report.totalClasses)}</span>
          </div>
        </article>
      ''')
      ..writeln('</section>')
      ..writeln(classSections.toString())
      ..writeln(
        '<div class="generated">তৈরি: ${_escape(formatDateTime(report.generatedAt, english: false))}</div>',
      )
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  /// Uses the identical native/fallback converter pair as the financial report.
  static Future<Uint8List> _convertHtmlToPdf(String html) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return await HtmlToPdfConverter().convertHtmlToPdfBytes(html: html);
      } catch (e) {
        debugPrint('All students report: native HTML to PDF failed: $e');
      }
    }
    // ignore: deprecated_member_use
    return Printing.convertHtml(format: PdfPageFormat.a4, html: html);
  }

  static Future<Uint8List> buildPdf({
    required AllStudentsReportData report,
    required String academyId,
  }) async {
    String academyName = 'একাডেমি ম্যানেজমেন্ট সিস্টেম';
    String address = '';
    String phone = '';
    Academy? academy;

    try {
      academy = await AcademyRepository().fetchById(academyId);
      if (academy != null) {
        if (academy.name.trim().isNotEmpty) academyName = academy.name.trim();
        address = academy.address?.trim() ?? '';
        phone = academy.phone?.trim() ?? '';
      }
    } catch (_) {
      // Academy metadata is optional; the generic header is still valid.
    }

    final fontBase64 = await _loadFontBase64();
    final logoDataUri = await _loadLogoDataUri(academy);
    final html = await _buildHtml(
      report: report,
      academyName: academyName,
      address: address,
      phone: phone,
      fontBase64: fontBase64,
      logoDataUri: logoDataUri,
    );
    return _convertHtmlToPdf(html);
  }

  // ---------------------------------------------------------------------------
  // Local storage
  // ---------------------------------------------------------------------------

  static Future<Directory> _resolveDirectory() async {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      try {
        if (await downloads.exists()) return downloads;
        await downloads.create(recursive: true);
        if (await downloads.exists()) return downloads;
      } catch (_) {
        // Scoped storage may deny this path; fall back to the app documents dir.
      }
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (_) {
      // getDownloadsDirectory is unsupported on some platforms.
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<List<SavedAllStudentsPdf>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <SavedAllStudentsPdf>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedAllStudentsPdf>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SavedAllStudentsPdf.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('All students report metadata read skipped: $e');
      return <SavedAllStudentsPdf>[];
    }
  }

  static Future<void> _writeAll(List<SavedAllStudentsPdf> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  static Future<SavedAllStudentsPdf> savePdf({
    required String academyId,
    required Uint8List bytes,
    required AllStudentsReportData report,
  }) async {
    final directory = await _resolveDirectory();
    final now = DateTime.now();
    final stamp =
        '${DateFormat('yyyyMMdd_HHmmss').format(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final fileName = 'all_students_report_$stamp.pdf';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final record = SavedAllStudentsPdf(
      id: '${now.microsecondsSinceEpoch}',
      academyId: academyId,
      fileName: fileName,
      filePath: file.path,
      generatedAt: report.generatedAt,
      createdAt: now,
      fileSize: await file.length(),
      studentCount: report.totalStudents,
      classCount: report.totalClasses,
    );

    final records = await _readAll();
    records.add(record);
    await _writeAll(records);
    return record;
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<List<SavedAllStudentsPdf>> loadSaved({
    required String academyId,
  }) async {
    final records = await _readAll();
    final visible =
        records
            .where((item) => item.academyId == academyId)
            .where((item) => _fileExists(item.filePath))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  static Future<void> delete(SavedAllStudentsPdf record) async {
    final records = await _readAll();
    await _writeAll(records.where((item) => item.id != record.id).toList());
    try {
      final file = File(record.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('All students report file delete skipped: $e');
    }
  }
}
