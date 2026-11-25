import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/models/academy.dart';
import 'package:academy_management/models/due_students_report.dart';
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

/// Fetches, aggregates, renders and stores the class-wise due-students PDF.
///
/// The PDF is intentionally rendered with the exact HTML/CSS pipeline used by
/// [FinancialReportService]: a real Bengali TTF is embedded as a base64 data URI
/// so conjuncts, matras and Bengali digits shape correctly, then the native
/// WebView converter (or the `printing` fallback) prints the same markup.
abstract final class DueStudentsReportService {
  static const List<String> _fontAssets = [
    'assets/fonts/HindSiliguri-Regular.ttf',
    'assets/fonts/Ekush-Regular.ttf',
  ];
  static const String _logoAsset = 'assets/images/institute_logo.png';
  static const String _prefsKey = 'due_students_pdf_reports_v1';

  /// Canonical month names are taken from the financial report so the due PDF
  /// uses the same Bengali spelling everywhere.
  static const List<String> _months = FinancialReportService.banglaMonths;

  static const Map<int, List<String>> _monthAliases = {
    1: ['জানুয়ারি', 'জানুয়ারি', 'জানু', 'january', 'jan'],
    2: ['ফেব্রুয়ারি', 'ফেব্রুয়ারি', 'ফেব্রু', 'february', 'feb'],
    3: ['মার্চ', 'march', 'mar'],
    4: ['এপ্রিল', 'april', 'apr'],
    5: ['মে', 'may'],
    6: ['জুন', 'june', 'jun'],
    7: ['জুলাই', 'july', 'jul'],
    8: ['আগস্ট', 'আগেষ্ট', 'august', 'aug'],
    9: ['সেপ্টেম্বর', 'সেপ্টেম্বর', 'september', 'sep', 'sept'],
    10: ['অক্টোবর', 'অক্টোবার', 'october', 'oct'],
    11: ['নভেম্বর', 'নভেম্বার', 'november', 'nov'],
    12: ['ডিসেম্বর', 'ডিসেম্বার', 'december', 'dec'],
  };

  // ---------------------------------------------------------------------------
  // Public formatting helpers (mirror the financial report API).
  // ---------------------------------------------------------------------------

  static String formatDateTime(DateTime value, {required bool english}) =>
      FinancialReportService.formatDateTime(value, english: english);

  static String money(double value, {required bool english}) =>
      FinancialReportService.money(value, english: english);

  // ---------------------------------------------------------------------------
  // Data loading and aggregation
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

  /// Accepts Bengali/English month names, `1`..`12`, `01/2026`, `2026-01`, etc.
  static int? _monthNumber(dynamic value) {
    final raw = _toAsciiDigits(value?.toString() ?? '').trim().toLowerCase();
    if (raw.isEmpty) return null;

    final normalized = raw
        .replaceAll(RegExp(r'[\s\-_/,().|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();

    for (final entry in _monthAliases.entries) {
      for (final alias in entry.value) {
        if (tokens.any((token) => token == alias)) return entry.key;
      }
    }
    for (final entry in _monthAliases.entries) {
      for (final alias in entry.value) {
        if (alias.length < 3) continue;
        if (tokens.any((token) => token.startsWith(alias))) return entry.key;
      }
    }

    final yearFirst = RegExp(
      r'(\d{4})\s*[-/]\s*(\d{1,2})',
    ).firstMatch(normalized);
    if (yearFirst != null) {
      final number = int.tryParse(yearFirst.group(2)!);
      if (number != null && number >= 1 && number <= 12) return number;
    }
    final monthFirst = RegExp(
      r'^(\d{1,2})\s*[-/]\s*\d{4}',
    ).firstMatch(normalized);
    if (monthFirst != null) {
      final number = int.tryParse(monthFirst.group(1)!);
      if (number != null && number >= 1 && number <= 12) return number;
    }
    for (final token in tokens) {
      final number = int.tryParse(token);
      if (number != null && number >= 1 && number <= 12) return number;
    }
    return null;
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

  static Future<List<Map<String, dynamic>>> _rows(
    String table,
    String columns,
    String academyId,
  ) async {
    final response = await Supabase.instance.client
        .from(table)
        .select(columns)
        .eq('academy_id', academyId);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<DueStudentsReportData> fetchReport({
    required String academyId,
  }) async {
    final studentRows = await _rows('students', '*', academyId);
    final feeRows = await _rows(
      'student_fee_history',
      'student_id, amount, month',
      academyId,
    );

    final paidMonthsByStudent = <String, Set<int>>{};
    for (final row in feeRows) {
      final studentId = row['student_id']?.toString().trim() ?? '';
      final monthNumber = _monthNumber(row['month']);
      final amount = _amount(row['amount']);
      if (studentId.isEmpty || monthNumber == null || amount <= 0) continue;
      paidMonthsByStudent
          .putIfAbsent(studentId, () => <int>{})
          .add(monthNumber);
    }

    final now = DateTime.now();
    final applicableMonths = List<int>.generate(
      now.month,
      (index) => index + 1,
    );
    final grouped = <String, List<DueStudentRecord>>{};

    for (final row in studentRows) {
      final studentId = row['id']?.toString().trim() ?? '';
      final monthlyFee = _amount(row['monthly_fee']);
      final paidMonths = paidMonthsByStudent[studentId] ?? const <int>{};
      final pendingMonths = applicableMonths
          .where((month) => !paidMonths.contains(month))
          .map((month) => _months[month - 1])
          .toList();
      if (pendingMonths.isEmpty || monthlyFee <= 0) continue;

      final className = _text(row, const [
        'class',
        'class_name',
      ], 'অন্যান্য ক্লাস');
      final student = DueStudentRecord(
        studentId: studentId,
        name: _text(row, const ['full_name', 'name'], 'নামহীন শিক্ষার্থী'),
        fatherName: _text(row, const [
          'father_name',
          'guardian_name',
        ], 'পাওয়া যায়নি'),
        roll: _text(row, const ['roll', 'roll_no'], 'নেই'),
        className: className,
        monthlyFee: monthlyFee,
        pendingMonths: pendingMonths,
        dueAmount: monthlyFee * pendingMonths.length,
      );
      grouped.putIfAbsent(className, () => <DueStudentRecord>[]).add(student);
    }

    final classes = grouped.entries.map((entry) {
      final students = entry.value.toList()
        ..sort((a, b) {
          final aRoll = int.tryParse(_toAsciiDigits(a.roll)) ?? 999999;
          final bRoll = int.tryParse(_toAsciiDigits(b.roll)) ?? 999999;
          if (aRoll != bRoll) return aRoll.compareTo(bRoll);
          return a.name.compareTo(b.name);
        });
      return DueClassGroup(className: entry.key, students: students);
    }).toList()..sort((a, b) => a.className.compareTo(b.className));

    return DueStudentsReportData(generatedAt: now, classes: classes);
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
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        bytes[5] == 0x61) {
      return 'image/gif';
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

  static String _classTableHtml(DueClassGroup group) {
    final body = StringBuffer();
    for (final student in group.students) {
      body.writeln(
        '<tr>'
        '<td>${_escape(student.name)}</td>'
        '<td>${_escape(student.roll)}</td>'
        '<td>${_escape(student.fatherName)}</td>'
        '<td>${_escape(student.pendingMonths.join(', '))}</td>'
        '<td class="amount">${_escape(bnNum(student.dueAmount))}</td>'
        '</tr>',
      );
    }

    return '''
      <table class="ledger">
        <colgroup>
          <col style="width: 25%" />
          <col style="width: 10%" />
          <col style="width: 21%" />
          <col style="width: 32%" />
          <col style="width: 12%" />
        </colgroup>
        <thead>
          <tr>
            <th>শিক্ষার্থী</th>
            <th>রোল</th>
            <th>বাবার নাম</th>
            <th>বকেয়া মাস</th>
            <th class="amount">বকেয়া (৳)</th>
          </tr>
        </thead>
        <tbody>
          $body
        </tbody>
      </table>
    ''';
  }

  static String _buildHtml({
    required DueStudentsReportData report,
    required String academyName,
    required String address,
    required String phone,
    required String fontBase64,
    required String? logoDataUri,
  }) {
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
    for (final group in report.classes) {
      classSections.writeln('''
        <section class="class-block">
          <h2 class="class-title">
            ${_escape(group.className)}
            <span class="class-count">${bn(group.studentCount)} জন</span>
            <span class="class-due">${_escape(money(group.dueAmount, english: false))}</span>
          </h2>
          <div class="class-months">বকেয়া মাস: ${_escape(group.pendingMonths.join(', '))}</div>
          ${_classTableHtml(group)}
        </section>
      ''');
    }
    if (report.classes.isEmpty) {
      classSections.writeln(
        '<div class="empty">চলতি শিক্ষাবর্ষে কোনো বকেয়া শিক্ষার্থী পাওয়া যায়নি।</div>',
      );
    }

    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="bn">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8" />')
      ..writeln('<title>বকেয়া শিক্ষার্থীদের রিপোর্ট</title>')
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
        font-size: 10.5px;
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
        font-size: 10.5px;
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
      .students { color: #dc2626; }
      .due { color: #b91c1c; }
      .classes { color: #0f766e; }
      .months { color: #1d4ed8; }
      .class-block { margin-top: 14px; }
      .class-title {
        margin: 0 0 4px;
        padding: 6px 8px;
        border-radius: 6px;
        background: #fef2f2;
        color: #991b1b;
        font-size: 12px;
        font-weight: 700;
        overflow-wrap: anywhere;
      }
      .class-count { margin-left: 8px; font-size: 10px; color: #64748b; }
      .class-due { margin-left: 8px; font-size: 10px; color: #b91c1c; }
      .class-months {
        margin-bottom: 5px;
        font-size: 9.5px;
        color: #475569;
        overflow-wrap: anywhere;
      }
      .ledger {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      .ledger thead { display: table-header-group; }
      .ledger tr { break-inside: avoid; page-break-inside: avoid; }
      .ledger th,
      .ledger td {
        padding: 6px;
        border: 1px solid #e2e8f0;
        text-align: left;
        vertical-align: top;
        font-size: 9.5px;
        overflow-wrap: anywhere;
        word-break: break-word;
      }
      .ledger th {
        background: #0f766e;
        color: #ffffff;
        font-weight: 700;
        border-color: #0f766e;
      }
      .ledger .amount { text-align: right; }
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
      ..writeln('<div class="report-title">বকেয়া শিক্ষার্থীদের রিপোর্ট</div>')
      ..writeln(
        '<div class="header-range">তৈরি: ${_escape(formatDateTime(report.generatedAt, english: false))}</div>',
      )
      ..writeln('</div>')
      ..writeln('</header>')
      ..writeln('<section class="summary-grid">')
      ..writeln('''
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">মোট বকেয়া শিক্ষার্থী</span>
            <span class="metric-value students">${bn(report.totalStudents)} জন</span>
          </div>
          <div class="metric">
            <span class="metric-label">মোট বকেয়া</span>
            <span class="metric-value due">${_escape(money(report.totalDueAmount, english: false))}</span>
          </div>
        </article>
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">ক্লাস সংখ্যা</span>
            <span class="metric-value classes">${bn(report.totalClasses)}</span>
          </div>
          <div class="metric">
            <span class="metric-label">মোট বকেয়া মাস</span>
            <span class="metric-value months">${bn(report.totalPendingMonths)}</span>
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
        debugPrint('Due students report: native HTML to PDF failed: $e');
      }
    }
    // ignore: deprecated_member_use
    return Printing.convertHtml(format: PdfPageFormat.a4, html: html);
  }

  static Future<Uint8List> buildPdf({
    required DueStudentsReportData report,
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
    final html = _buildHtml(
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

  static Future<List<SavedDueStudentsPdf>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <SavedDueStudentsPdf>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedDueStudentsPdf>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SavedDueStudentsPdf.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('Due students report metadata read skipped: $e');
      return <SavedDueStudentsPdf>[];
    }
  }

  static Future<void> _writeAll(List<SavedDueStudentsPdf> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  static Future<SavedDueStudentsPdf> savePdf({
    required String academyId,
    required Uint8List bytes,
    required DueStudentsReportData report,
  }) async {
    final directory = await _resolveDirectory();
    final now = DateTime.now();
    final stamp =
        '${DateFormat('yyyyMMdd_HHmmss').format(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final fileName = 'due_students_report_$stamp.pdf';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final record = SavedDueStudentsPdf(
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

  static Future<List<SavedDueStudentsPdf>> loadSaved({
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

  static Future<void> delete(SavedDueStudentsPdf record) async {
    final records = await _readAll();
    await _writeAll(records.where((item) => item.id != record.id).toList());
    try {
      final file = File(record.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Due students report file delete skipped: $e');
    }
  }
}
