import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/utils/pdf_helper.dart';
import '../domain/report_models.dart';

class ReportPdf {
  static Future<Uint8List> build(PreparedReport report) async {
    final s = report.snapshot;
    final regular = pw.Font.ttf(
      await rootBundle.load(PdfHelper.regularFontAsset),
    );
    final bold = pw.Font.ttf(await rootBundle.load(PdfHelper.boldFontAsset));
    final logo = s['logo'] == null
        ? null
        : pw.MemoryImage(base64Decode(s['logo'] as String));
    final pdf = pw.Document(
      title: s['title'] as String,
      author: s['officeName'] as String,
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        margin: const pw.EdgeInsets.all(36),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => pw.Column(
          children: [
            if (logo != null)
              pw.Image(logo, height: 42, width: 90, fit: pw.BoxFit.contain),
            pw.Text(
              s['officeName'] as String,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
            ),
            pw.Text(
              s['title'] as String,
              style: const pw.TextStyle(fontSize: 15),
            ),
            pw.Divider(),
          ],
        ),
        footer: (c) => pw.Center(
          child: pw.Text(
            'صفحة ${c.pageNumber} من ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => [
          pw.Text('الموكل: ${s['clientName']}'),
          if (s['caseNumber'] != null) pw.Text('القضية: ${s['caseNumber']}'),
          pw.Text('تاريخ الإعداد: ${s['date']}'),
          pw.SizedBox(height: 14),
          for (final section in s['sections'] as List) ...[
            pw.NewPage(freeSpace: 75),
            pw.Text(
              section['label'] as String,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
            pw.SizedBox(height: 5),
            for (final paragraph in _paragraphs(section['text'] as String)) ...[
              pw.NewPage(freeSpace: 150),
              pw.Text(
                paragraph,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
              ),
              pw.SizedBox(height: 5),
            ],
            pw.SizedBox(height: 10),
          ],
          pw.NewPage(freeSpace: 60),
          pw.Divider(),
          pw.Text('المحامي: ${s['lawyerName']}'),
          if ((s['lawyerPhone'] as String).isNotEmpty)
            pw.Text('هاتف المكتب / المحامي: ${s['lawyerPhone']}'),
        ],
      ),
    );
    return pdf.save();
  }

  static Iterable<String> _paragraphs(String text) sync* {
    for (var line in text.split('\n')) {
      while (line.length > 500) {
        var cut = line.lastIndexOf(' ', 500);
        if (cut < 100) cut = 500;
        yield line.substring(0, cut);
        line = line.substring(cut).trimLeft();
      }
      if (line.isNotEmpty) yield line;
    }
  }

  static Future<List<Uint8List>> images(Uint8List pdf) async {
    final result = <Uint8List>[];
    await for (final page in Printing.raster(pdf, dpi: 110)) {
      result.add(await page.toPng());
      if (result.length > 200) {
        throw const FormatException(
          'التقرير طويل جدًا؛ قلّل المحتوى أو استخدم PDF.',
        );
      }
    }
    if (result.isEmpty) throw const FormatException('تعذر إنشاء صور التقرير.');
    return result;
  }
}
