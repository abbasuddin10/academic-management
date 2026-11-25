import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';

import 'result_calculator.dart';
import '../widgets/result_sheet.dart';

/// Builds the canonical A4 result sheet and reuses it for in-app preview,
/// single-student print and bulk print (one page per student).
abstract final class ResultPdfService {
  static const String _fontAsset = 'assets/fonts/Ekush-Regular.ttf';

  /// Safely downloads an image URL into bytes. Returns null on any failure —
  /// the result sheet has clean fallbacks for a missing logo/photo/signature.
  static Future<Uint8List?> fetchImageBytes(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final response = await Dio().get<List<int>>(
        url.trim(),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (e) {
      debugPrint('Result sheet image load skipped: $e');
      return null;
    }
  }

  /// Captures the SAME widget shown on the View screen.
  ///
  /// CRITICAL: `targetSize` tells screenshot to lay the widget out inside an
  /// A4-sized RenderView. Without it the package uses the DEVICE SCREEN size,
  /// so the 794x1123 sheet overflows that view on all four sides (yellow/black
  /// overflow stripes) and the captured bitmap is cropped to the screen.
  /// With `targetSize` the logical constraints are exactly A4, `UnconstrainedBox`
  /// is unnecessary, and the PDF is a pixel-exact copy of the preview.
  static Future<Uint8List> captureSheet(ResultSheetData data) async {
    final controller = ScreenshotController();
    const a4Size = Size(ResultSheet.sheetWidth, ResultSheet.sheetHeight);
    try {
      return await controller.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: a4Size,
            textScaler: TextScaler.linear(1),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Material(
              color: Colors.white,
              child: SizedBox(
                width: a4Size.width,
                height: a4Size.height,
                child: ResultSheet(data: data),
              ),
            ),
          ),
        ),
        targetSize: a4Size,
        pixelRatio: 3.0,
        delay: const Duration(milliseconds: 300),
      );
    } catch (e) {
      debugPrint('Widget capture failed, using native PDF sheet: $e');
      return _renderNativeSheet(data);
    }
  }

  /// One A4 page per captured sheet — N students produce N clean pages.
  static Future<Uint8List> buildPdf(List<Uint8List> sheetImages) async {
    final document = pw.Document();
    final pageFormat = pw_pdf.PdfPageFormat.a4;

    for (final imageBytes in sheetImages) {
      document.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(
            pw.MemoryImage(imageBytes),
            width: pageFormat.width,
            height: pageFormat.height,
            // The captured image is A4-proportioned; `contain` guards against
            // any rounding drift so nothing is stretched or clipped.
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    }
    if (sheetImages.isEmpty) {
      document.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Center(
            child: pw.Text(
              'No result sheets to print.',
              style: pw.TextStyle(fontSize: 12),
            ),
          ),
        ),
      );
    }
    return document.save();
  }

  /// Opens the platform print / save / share preview.
  static Future<void> preview(
    Uint8List bytes, {
    required String filename,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: filename,
    );
  }

  // ---------------------------------------------------------------------------
  // Native pw fallback — mirrors the widget's structure with constrained,
  // wrapped cells so text never clips even if widget capture is unavailable.
  // ---------------------------------------------------------------------------
  static Future<Uint8List> _renderNativeSheet(ResultSheetData data) async {
    pw.Font font;
    try {
      font = pw.Font.ttf(await rootBundle.load(_fontAsset));
    } catch (_) {
      font = pw.Font.helvetica();
    }
    pw.TextStyle style(double size, {bool bold = false, pw_pdf.PdfColor? color}) {
      return pw.TextStyle(
        font: font,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : null,
        color: color ?? const pw_pdf.PdfColor.fromInt(0xFF1F2937),
      );
    }
    pw.Widget cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Wrap(
        children: [
          pw.Text(
            text.trim().isEmpty ? '-' : text,
            style: style(9, bold: bold),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    final subjects = ResultCalculator.subjects(data.resultData).toList();
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

    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: pw_pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '${data.academy['academy_name'] ?? 'Academy'}',
              style: style(18, bold: true),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${data.academy['address'] ?? ''}',
              style: style(9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'EIIN: ${data.academy['eiin'] ?? '-'}    Code: ${data.academy['academy_code'] ?? '-'}',
              style: style(9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              color: const pw_pdf.PdfColor.fromInt(0xFF1B365D),
              child: pw.Text(
                'RESULT SHEET  |  ${data.examTitle}  |  Class: ${data.className}',
                style: style(12, bold: true, color: pw_pdf.PdfColors.white),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '${data.student['name'] ?? 'Student'}  •  Roll: $roll  •  Position: $position',
              style: style(11, bold: true),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'GPA: ${gpa.toStringAsFixed(2)} / 5.00   Grade: ${grade.label}   Percentage: ${percent.label}',
              style: style(10),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: pw_pdf.PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(1.2),
                5: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  children: [
                    cell('Subject', bold: true),
                    cell('CQ', bold: true),
                    cell('MCQ', bold: true),
                    cell('Viva', bold: true),
                    cell('Practical', bold: true),
                    cell('Total', bold: true),
                  ],
                ),
                ...subjects.map((subject) {
                  final cq = ResultCalculator.mark(data.resultData, subject, 'cq');
                  final mcq = ResultCalculator.mark(data.resultData, subject, 'mcq');
                  final viva = ResultCalculator.mark(data.resultData, subject, 'viva');
                  final practical =
                      ResultCalculator.mark(data.resultData, subject, 'practical');
                  return pw.TableRow(
                    children: [
                      cell(subject),
                      cell('${cq.round()}'),
                      cell('${mcq.round()}'),
                      cell('${viva.round()}'),
                      cell('${practical.round()}'),
                      cell('${(cq + mcq + viva + practical).round()}', bold: true),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  children: [
                    pw.SizedBox(height: 34),
                    pw.Container(width: 150, height: 1, color: pw_pdf.PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Head of Institution',
                      style: style(10, bold: true),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return document.save();
  }
}
