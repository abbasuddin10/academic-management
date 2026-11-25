import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/models/academy.dart';
import 'package:academy_management/models/teacher_salary_history_report.dart';
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

/// Fetches, groups, renders and stores the teacher salary history PDF.
///
/// The PDF uses the exact HTML/CSS pipeline as the financial, due and
/// all-students reports: a real Bengali TTF embedded as a base64 data URI and
/// the native WebView converter (with a `printing` fallback).
abstract final class TeacherSalaryHistoryReportService {
  static const List<String> _fontAssets = [
    'assets/fonts/HindSiliguri-Regular.ttf',
    'assets/fonts/Ekush-Regular.ttf',
  ];
  static const String _logoAsset = 'assets/images/institute_logo.png';
  static const String _prefsKey = 'teacher_salary_pdf_reports_v1';
  static const List<String> _roles = ['teacher', 'staff', 'super_admin'];

  // ---------------------------------------------------------------------------
  // Public formatting helpers (mirror the other report services).
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

  /// Mirrors the payable calculation used by the salary dashboard/screen:
  /// salary for every month from joining month through the current month,
  /// with a missing/invalid date treated as one payable month.
  static double _payableSalary({
    required double monthlySalary,
    required String joinedAt,
    required DateTime now,
  }) {
    final joined = DateTime.tryParse(joinedAt)?.toLocal();
    var totalMonths = 1;
    if (joined != null) {
      totalMonths =
          (now.year - joined.year) * 12 + now.month - joined.month + 1;
      if (totalMonths < 1) totalMonths = 1;
    }
    return monthlySalary * totalMonths;
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

  /// `select('*')` is intentional: the repo has no migration creating these
  /// tables, so explicit column lists could fail on an older installation.
  static Future<TeacherSalaryHistoryReportData> fetchReport({
    required String academyId,
  }) async {
    final supabase = Supabase.instance.client;
    final userRows =
        (await supabase
                    .from('users')
                    .select('*')
                    .eq('academy_id', academyId)
                    .inFilter('role', _roles)
                as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
    final historyRows =
        (await supabase
                    .from('teacher_salary_history')
                    .select('*')
                    .eq('academy_id', academyId)
                as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();

    final paymentsByTeacher = <String, List<TeacherSalaryPayment>>{};
    for (final row in historyRows) {
      final teacherId = _text(row, const ['teacher_id'], '');
      if (teacherId.isEmpty) continue;
      paymentsByTeacher
          .putIfAbsent(teacherId, () => [])
          .add(
            TeacherSalaryPayment(
              month: _text(row, const ['month'], '—'),
              paymentDate: _text(row, const [
                'payment_date',
                'date',
              ], _text(row, const ['created_at'], '—')),
              amount: _amount(row['amount']),
              createdAt: _text(row, const ['created_at'], ''),
            ),
          );
    }

    final now = DateTime.now();
    final teachers = userRows.map((row) {
      final id = _text(row, const ['id'], '');
      final payments =
          (paymentsByTeacher[id] ?? const <TeacherSalaryPayment>[]).toList()
            ..sort((a, b) {
              final aDate = DateTime.tryParse(a.createdAt);
              final bDate = DateTime.tryParse(b.createdAt);
              if (aDate != null && bDate != null) return bDate.compareTo(aDate);
              return b.paymentDate.compareTo(a.paymentDate);
            });
      final monthlySalary = _amount(row['salary']);
      final joinedAt = _text(row, const ['created_at'], '');
      final totalPayable = _payableSalary(
        monthlySalary: monthlySalary,
        joinedAt: joinedAt,
        now: now,
      );
      final totalPaid = payments.fold<double>(
        0.0,
        (sum, payment) => sum + payment.amount,
      );
      final totalDue = (totalPayable - totalPaid) > 0
          ? totalPayable - totalPaid
          : 0.0;
      return TeacherSalaryGroup(
        teacherId: id,
        name: _text(row, const ['full_name', 'name'], 'নামহীন শিক্ষক'),
        role: _text(row, const ['role'], 'শিক্ষক'),
        phone: _text(row, const ['phone', 'mobile'], 'নেই'),
        email: _text(row, const ['email'], 'নেই'),
        monthlySalary: monthlySalary,
        joinedAt: joinedAt,
        payments: payments,
        totalPayable: totalPayable,
        totalDue: totalDue,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    return TeacherSalaryHistoryReportData(generatedAt: now, teachers: teachers);
  }

  // ---------------------------------------------------------------------------
  // PDF rendering (HTML + CSS) — same mechanism as the other reports
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

  static String _teacherCardHtml(TeacherSalaryGroup teacher) {
    final rows = StringBuffer();
    for (final payment in teacher.payments) {
      rows.writeln(
        '<tr>'
        '<td>${_escape(bn(payment.month))}</td>'
        '<td>${_escape(bn(payment.paymentDate))}</td>'
        '<td class="amount">${_escape(money(payment.amount, english: false))}</td>'
        '</tr>',
      );
    }
    final table = teacher.payments.isEmpty
        ? '<div class="empty">কোনো বেতন প্রদানের ইতিহাস পাওয়া যায়নি।</div>'
        : '''
          <table class="ledger">
            <colgroup>
              <col style="width: 34%" /><col style="width: 36%" /><col style="width: 30%" />
            </colgroup>
            <thead>
              <tr><th>মাস</th><th>প্রদানের তারিখ</th><th class="amount">পরিমাণ</th></tr>
            </thead>
            <tbody>
              $rows
            </tbody>
          </table>
        ''';

    return '''
      <article class="teacher-card">
        <div class="teacher-head">
          <span class="teacher-name">${_escape(teacher.name)}</span>
          <span class="teacher-role">${_escape(bn(teacher.role))}</span>
        </div>
        <div class="teacher-meta">
          <span>মোবাইল: ${_escape(bn(teacher.phone))}</span>
          <span>ইমেইল: ${_escape(teacher.email)}</span>
          <span>মাসিক বেতন: ${_escape(money(teacher.monthlySalary, english: false))}</span>
        </div>
        <div class="teacher-total">
          <span>মোট প্রদান: ${_escape(money(teacher.totalPaid, english: false))}</span>
          <span class="due">ডিউ / পাওনা: ${_escape(money(teacher.totalDue, english: false))}</span>
        </div>
        $table
      </article>
    ''';
  }

  static String _buildHtml({
    required TeacherSalaryHistoryReportData report,
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

    final sections = StringBuffer();
    for (final teacher in report.teachers) {
      sections.writeln(_teacherCardHtml(teacher));
    }
    if (report.teachers.isEmpty) {
      sections.writeln(
        '<div class="empty">এই একাডেমিতে কোনো শিক্ষক বা স্টাফ পাওয়া যায়নি।</div>',
      );
    }

    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="bn">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8" />')
      ..writeln('<title>শিক্ষক বেতন ইতিহাস রিপোর্ট</title>')
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
      .teachers { color: #0f766e; }
      .paid { color: #15803d; }
      .due { color: #b45309; }
      .salary { color: #475569; font-size: 12px; }
      .teacher-card {
        margin-top: 12px;
        border: 1px solid #cbd5e1;
        border-radius: 6px;
        overflow: hidden;
        break-inside: avoid;
        page-break-inside: avoid;
      }
      .teacher-head {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 8px;
        background: #f0fdfa;
        border-bottom: 1px solid #cbd5e1;
      }
      .teacher-name {
        flex: 1 1 auto;
        min-width: 0;
        font-size: 11px;
        font-weight: 700;
        color: #0f172a;
        overflow-wrap: anywhere;
        word-break: break-word;
      }
      .teacher-role {
        flex: 0 0 auto;
        padding: 1px 6px;
        border-radius: 8px;
        background: #ccfbf1;
        color: #115e59;
        font-size: 9px;
        overflow-wrap: anywhere;
      }
      .teacher-meta,
      .teacher-total {
        display: flex;
        flex-wrap: wrap;
        gap: 4px 12px;
        padding: 5px 8px;
        font-size: 9px;
        color: #475569;
        overflow-wrap: anywhere;
      }
      .teacher-total {
        background: #f8fafc;
        color: #15803d;
        font-weight: 700;
        border-top: 1px solid #e2e8f0;
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
        padding: 5px 6px;
        border: 1px solid #e2e8f0;
        text-align: left;
        vertical-align: top;
        font-size: 9px;
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
        margin: 8px;
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
      ..writeln('<div class="report-title">শিক্ষক বেতন ইতিহাস রিপোর্ট</div>')
      ..writeln(
        '<div class="header-range">তৈরি: ${_escape(formatDateTime(report.generatedAt, english: false))}</div>',
      )
      ..writeln('</div>')
      ..writeln('</header>')
      ..writeln('<section class="summary-grid">')
      ..writeln('''
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">মোট শিক্ষক / স্টাফ</span>
            <span class="metric-value teachers">${bn(report.totalTeachers)} জন</span>
          </div>
          <div class="metric">
            <span class="metric-label">টোটাল ডিউ</span>
            <span class="metric-value due">${_escape(money(report.totalDue, english: false))}</span>
          </div>
        </article>
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">মোট পরিশোধিত বেতন</span>
            <span class="metric-value paid">${_escape(money(report.totalPaid, english: false))}</span>
          </div>
          <div class="metric">
            <span class="metric-label">মোট মাসিক বেতন</span>
            <span class="metric-value salary">${_escape(money(report.totalMonthlySalary, english: false))}</span>
          </div>
        </article>
      ''')
      ..writeln('</section>')
      ..writeln(sections.toString())
      ..writeln(
        '<div class="generated">তৈরি: ${_escape(formatDateTime(report.generatedAt, english: false))}</div>',
      )
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  /// Uses the identical native/fallback converter pair as the other reports.
  static Future<Uint8List> _convertHtmlToPdf(String html) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return await HtmlToPdfConverter().convertHtmlToPdfBytes(html: html);
      } catch (e) {
        debugPrint(
          'Teacher salary history report: native HTML to PDF failed: $e',
        );
      }
    }
    // ignore: deprecated_member_use
    return Printing.convertHtml(format: PdfPageFormat.a4, html: html);
  }

  static Future<Uint8List> buildPdf({
    required TeacherSalaryHistoryReportData report,
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

  static Future<List<SavedTeacherSalaryPdf>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <SavedTeacherSalaryPdf>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedTeacherSalaryPdf>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SavedTeacherSalaryPdf.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('Teacher salary history metadata read skipped: $e');
      return <SavedTeacherSalaryPdf>[];
    }
  }

  static Future<void> _writeAll(List<SavedTeacherSalaryPdf> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  static Future<SavedTeacherSalaryPdf> savePdf({
    required String academyId,
    required Uint8List bytes,
    required TeacherSalaryHistoryReportData report,
  }) async {
    final directory = await _resolveDirectory();
    final now = DateTime.now();
    final stamp =
        '${DateFormat('yyyyMMdd_HHmmss').format(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final fileName = 'teacher_salary_history_$stamp.pdf';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final record = SavedTeacherSalaryPdf(
      id: '${now.microsecondsSinceEpoch}',
      academyId: academyId,
      fileName: fileName,
      filePath: file.path,
      generatedAt: report.generatedAt,
      createdAt: now,
      fileSize: await file.length(),
      teacherCount: report.totalTeachers,
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

  static Future<List<SavedTeacherSalaryPdf>> loadSaved({
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

  static Future<void> delete(SavedTeacherSalaryPdf record) async {
    final records = await _readAll();
    await _writeAll(records.where((item) => item.id != record.id).toList());
    try {
      final file = File(record.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Teacher salary history file delete skipped: $e');
    }
  }
}
