import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:academy_management/models/academy.dart';
import 'package:academy_management/models/financial_report.dart';
import 'package:academy_management/repositories/academy_repository.dart';
import 'package:academy_management/services/bengali_numbers.dart';
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

/// Fetches, renders, stores and lists the admin financial PDF reports.
///
/// Transaction data mirrors the existing "Academy Accounts" statement: student
/// fee collections, other income/expenses, other student collections and
/// teacher salary payments. Everything is filtered locally so a date *and*
/// time range works even for tables that only store a date string.
abstract final class FinancialReportService {
  /// A real Bengali TrueType font is required for PDF text and Bengali digits.
  static const List<String> _fontAssets = [
    'assets/fonts/HindSiliguri-Regular.ttf',
    'assets/fonts/Ekush-Regular.ttf',
  ];
  static const String _logoAsset = 'assets/images/institute_logo.png';
  static const String _prefsKey = 'financial_pdf_reports_v1';

  static const List<String> banglaMonths = [
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

  // ---------------------------------------------------------------------------
  // Formatting helpers shared by the UI and the PDF document.
  // ---------------------------------------------------------------------------

  static String formatDateTime(DateTime value, {required bool english}) {
    final local = value.toLocal();
    if (english) return DateFormat('dd MMM yyyy, HH:mm').format(local);
    final time =
        '${bn(local.hour.toString().padLeft(2, '0'))}:${bn(local.minute.toString().padLeft(2, '0'))}';
    return '${bn(local.day)} ${banglaMonths[local.month - 1]} ${bn(local.year)} · $time';
  }

  static String formatRange(
    DateTime start,
    DateTime end, {
    required bool english,
  }) {
    return '${formatDateTime(start, english: english)} → ${formatDateTime(end, english: english)}';
  }

  static String money(double value, {required bool english}) {
    if (english) return '৳ ${value.toStringAsFixed(2)}';
    return '৳ ${bnNum(value)}';
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  /// Parses ISO timestamps as well as `yyyy-MM-dd` / `dd-MM-yyyy` date strings.
  /// The record flag tells us whether the source had a time component.
  static ({DateTime date, bool dateOnly})? _parseDate(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      final match = RegExp(
        r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})',
      ).firstMatch(text);
      if (match != null) {
        parsed = DateTime.tryParse(
          '${match.group(3)}-${match.group(2)!.padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}',
        );
      }
    }
    if (parsed == null) return null;

    return (
      date: parsed.toLocal(),
      dateOnly: !text.contains('T') && !text.contains(':'),
    );
  }

  static bool _inRange(
    ({DateTime date, bool dateOnly}) parsed,
    DateTime start,
    DateTime end,
  ) {
    final date = parsed.date;
    if (!parsed.dateOnly) {
      return !date.isBefore(start) && !date.isAfter(end);
    }
    // A date-only row (e.g. payment_date) belongs to the whole calendar day.
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(DateTime(end.year, end.month, end.day));
  }

  static void _addTransaction(
    List<FinancialTransaction> output, {
    required dynamic dateValue,
    required String category,
    required bool isIncome,
    required dynamic amountValue,
    required String? note,
    required DateTime start,
    required DateTime end,
  }) {
    final parsed = _parseDate(dateValue);
    if (parsed == null || !_inRange(parsed, start, end)) return;

    final amount = double.tryParse(amountValue?.toString() ?? '') ?? 0.0;
    if (amount <= 0) return;

    output.add(
      FinancialTransaction(
        date: parsed.date,
        category: category,
        isIncome: isIncome,
        amount: amount,
        note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      ),
    );
  }

  static Future<FinancialReportData> fetchReport({
    required String academyId,
    required DateTime start,
    required DateTime end,
  }) async {
    final client = Supabase.instance.client;
    final transactions = <FinancialTransaction>[];
    var failedSources = 0;

    Future<List<Map<String, dynamic>>> rows(
      String table,
      String columns,
    ) async {
      try {
        final response = await client
            .from(table)
            .select(columns)
            .eq('academy_id', academyId);
        return (response as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      } catch (e) {
        debugPrint('Financial report: $table unavailable: $e');
        failedSources++;
        return <Map<String, dynamic>>[];
      }
    }

    // 1. Student fee collections (income).
    for (final row in await rows('student_fee_history', '*')) {
      final month = row['month']?.toString().trim() ?? '';
      _addTransaction(
        transactions,
        dateValue: row['created_at'] ?? row['payment_date'],
        category: month.isEmpty
            ? 'ছাত্রছাত্রীর ফি কালেকশন'
            : 'ছাত্রছাত্রীর ফি কালেকশন ($month)',
        isIncome: true,
        amountValue: row['amount'],
        note: null,
        start: start,
        end: end,
      );
    }

    // 2. Other income and expenses.
    for (final row in await rows('other_income_expenses', '*')) {
      final type = row['type']?.toString().toLowerCase().trim() ?? '';
      final isIncome = switch (type) {
        'income' || 'আয়' || 'আয়' || 'آئ' => true,
        'expense' || 'ব্যয়' || 'ব্যয়' || 'cost' => false,
        _ => null,
      };
      if (isIncome == null) continue;

      final title =
          row['title']?.toString().trim() ??
          row['category']?.toString().trim() ??
          '';
      final base = isIncome ? 'অন্যান্য আয়' : 'অন্যান্য ব্যয়';
      _addTransaction(
        transactions,
        dateValue: row['created_at'] ?? row['date'],
        category: title.isEmpty ? base : '$base ($title)',
        isIncome: isIncome,
        amountValue: row['amount'],
        note: row['note']?.toString(),
        start: start,
        end: end,
      );
    }

    // 3. Other student collections (income).
    for (final row in await rows('student_other_collections', '*')) {
      final category = row['category']?.toString().trim() ?? '';
      _addTransaction(
        transactions,
        dateValue: row['payment_date'] ?? row['created_at'],
        category: category.isEmpty
            ? 'অন্যান্য আয় (ছাত্র কালেকশন)'
            : 'অন্যান্য আয় ($category)',
        isIncome: true,
        amountValue: row['amount'],
        note: row['note']?.toString(),
        start: start,
        end: end,
      );
    }

    // 4. Teacher salary payments (expense).
    for (final row in await rows('teacher_salary_history', '*')) {
      final month = row['month']?.toString().trim() ?? '';
      _addTransaction(
        transactions,
        dateValue: row['created_at'] ?? row['payment_date'],
        category: month.isEmpty
            ? 'শিক্ষক বেতন পরিশোধ'
            : 'শিক্ষক বেতন পরিশোধ ($month)',
        isIncome: false,
        amountValue: row['amount'],
        note: null,
        start: start,
        end: end,
      );
    }

    if (failedSources == 4) {
      throw Exception(
        'আর্থিক তথ্য লোড করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
      );
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));
    return FinancialReportData(
      start: start,
      end: end,
      transactions: transactions,
    );
  }

  // ---------------------------------------------------------------------------
  // PDF rendering (HTML + CSS)
  // ---------------------------------------------------------------------------

  /// The `pdf` package cannot perform full Bengali conjunct shaping, so the
  /// report is rendered as HTML and printed by the native WebView instead.
  /// A real Bengali TTF is embedded as a data URI so shaping works offline.
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

  static String _escapeMultiline(Object? value) =>
      _escape(value).replaceAll('\n', '<br/>');

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

  static String _transactionTableHtml(List<FinancialTransaction> rows) {
    if (rows.isEmpty) {
      return '<div class="empty">এই সময়সীমায় কোনো লেনদেন নেই।</div>';
    }

    final body = StringBuffer();
    for (final item in rows) {
      final noteHtml = item.note == null
          ? ''
          : '<div class="note">${_escapeMultiline(item.note)}</div>';
      final typeClass = item.isIncome ? 'income' : 'expense';
      final typeLabel = item.isIncome ? 'আয়' : 'ব্যয়';
      body.writeln(
        '<tr>'
        '<td>${_escape(formatDateTime(item.date, english: false))}</td>'
        '<td>${_escapeMultiline(item.category)}$noteHtml</td>'
        '<td class="type $typeClass">$typeLabel</td>'
        '<td class="amount">${_escape(bnNum(item.amount))}</td>'
        '</tr>',
      );
    }

    return '''
      <table class="ledger">
        <colgroup>
          <col style="width: 25%" />
          <col style="width: 39%" />
          <col style="width: 12%" />
          <col style="width: 24%" />
        </colgroup>
        <thead>
          <tr>
            <th>তারিখ ও সময়</th>
            <th>খাত / বিবরণ</th>
            <th>ধরন</th>
            <th class="amount">পরিমাণ (৳)</th>
          </tr>
        </thead>
        <tbody>
          $body
        </tbody>
      </table>
    ''';
  }

  static String _buildHtml({
    required FinancialReportData report,
    required String academyName,
    required String address,
    required String phone,
    required String fontBase64,
    required String? logoDataUri,
    required DateTime generatedAt,
  }) {
    final incomeRows = report.transactions
        .where((item) => item.isIncome)
        .toList();
    final expenseRows = report.transactions
        .where((item) => !item.isIncome)
        .toList();
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

    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="bn">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8" />')
      ..writeln('<title>আর্থিক হিসাব</title>')
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
      .income { color: #15803d; }
      .expense { color: #dc2626; }
      .balance { color: #1d4ed8; }
      .count { color: #0f766e; }
      .statement { margin-top: 14px; }
      .section-title {
        margin: 0 0 6px;
        font-size: 12px;
        font-weight: 700;
      }
      .income-title { color: #15803d; }
      .expense-title { color: #dc2626; }
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
      .note {
        margin-top: 2px;
        font-size: 8.5px;
        color: #64748b;
      }
      .empty {
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
      ..writeln('<div class="report-title">আর্থিক হিসাব</div>')
      ..writeln(
        '<div class="header-range">${_escape(formatRange(report.start, report.end, english: false))}</div>',
      )
      ..writeln('</div>')
      ..writeln('</header>')
      ..writeln('<section class="summary-grid">')
      ..writeln('''
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">মোট আয়</span>
            <span class="metric-value income">${money(report.totalIncome, english: false)}</span>
          </div>
          <div class="metric">
            <span class="metric-label">মোট ব্যয়</span>
            <span class="metric-value expense">${money(report.totalExpense, english: false)}</span>
          </div>
        </article>
        <article class="summary-card">
          <div class="metric">
            <span class="metric-label">নিট ব্যালেন্স</span>
            <span class="metric-value balance">${money(report.netBalance, english: false)}</span>
          </div>
          <div class="metric">
            <span class="metric-label">মোট এন্ট্রি</span>
            <span class="metric-value count">${bn(report.entryCount)}</span>
          </div>
        </article>
      ''')
      ..writeln('</section>')
      ..writeln('<section class="statement">')
      ..writeln(
        '<h2 class="section-title income-title">আয়ের বিবরণ (${bn(incomeRows.length)}টি)</h2>',
      )
      ..writeln(_transactionTableHtml(incomeRows))
      ..writeln('</section>')
      ..writeln('<section class="statement">')
      ..writeln(
        '<h2 class="section-title expense-title">ব্যয়ের বিবরণ (${bn(expenseRows.length)}টি)</h2>',
      )
      ..writeln(_transactionTableHtml(expenseRows))
      ..writeln('</section>')
      ..writeln(
        '<div class="generated">তৈরি: ${_escape(formatDateTime(generatedAt, english: false))}</div>',
      )
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  /// Mobile rendering uses the native WebView converter; other platforms use
  /// the `printing` package's HTML renderer with the exact same markup.
  static Future<Uint8List> _convertHtmlToPdf(String html) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return await HtmlToPdfConverter().convertHtmlToPdfBytes(html: html);
      } catch (e) {
        debugPrint('Financial report: native HTML to PDF failed: $e');
      }
    }
    // ignore: deprecated_member_use
    return Printing.convertHtml(format: PdfPageFormat.a4, html: html);
  }

  static Future<Uint8List> buildPdf({
    required FinancialReportData report,
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
      generatedAt: DateTime.now(),
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

  static Future<List<SavedFinancialPdf>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return <SavedFinancialPdf>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedFinancialPdf>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SavedFinancialPdf.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('Financial report metadata read skipped: $e');
      return <SavedFinancialPdf>[];
    }
  }

  static Future<void> _writeAll(List<SavedFinancialPdf> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  static Future<SavedFinancialPdf> savePdf({
    required String academyId,
    required Uint8List bytes,
    required DateTime start,
    required DateTime end,
  }) async {
    final directory = await _resolveDirectory();
    final now = DateTime.now();
    final stamp =
        '${DateFormat('yyyyMMdd_HHmmss').format(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final fileName = 'financial_report_$stamp.pdf';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final record = SavedFinancialPdf(
      id: '${now.microsecondsSinceEpoch}',
      academyId: academyId,
      fileName: fileName,
      filePath: file.path,
      startAt: start,
      endAt: end,
      createdAt: now,
      fileSize: await file.length(),
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

  static Future<List<SavedFinancialPdf>> loadSaved({
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

  static Future<void> delete(SavedFinancialPdf record) async {
    final records = await _readAll();
    await _writeAll(records.where((item) => item.id != record.id).toList());
    try {
      final file = File(record.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Financial report file delete skipped: $e');
    }
  }
}
