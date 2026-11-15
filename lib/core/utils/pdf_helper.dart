import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:seneb_law/core/database/app_repository.dart';

class PdfHelper {
  static const regularFontAsset = 'assets/fonts/Tajawal-Regular.ttf';
  static const boldFontAsset = 'assets/fonts/Tajawal-Bold.ttf';

  /// Builds offline PDF bytes without invoking a printer or opening a dialog.
  static Future<Uint8List> buildDailyAgenda(
    List<SessionWithDetails> sessions,
    String title,
    DateTime date, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    AssetBundle? fontBundle,
  }) async {
    final bundle = fontBundle ?? rootBundle;
    final regular = pw.Font.ttf(await bundle.load(regularFontAsset));
    final bold = pw.Font.ttf(await bundle.load(boldFontAsset));
    final pdf = pw.Document(title: title, author: 'سِنِب للمحاماة');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'التاريخ: ${_date(date)}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Divider(color: PdfColors.indigo900),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        build: (_) => sessions.isEmpty
            ? [pw.Text('لا توجد جلسات مسجلة في هذا اليوم.')]
            : [
                for (var index = 0; index < sessions.length; index++) ...[
                  // تبقى بداية الجلسة واضحة عند الانتقال إلى صفحة جديدة.
                  pw.NewPage(freeSpace: 100),
                  _line(
                    '${index + 1}. القضية: ${sessions[index].caseEntity.caseNumber}',
                    bold: true,
                  ),
                  _line('الموكل: ${sessions[index].client.name}'),
                  _line(
                    'موعد الجلسة: ${_date(sessions[index].session.sessionDate)} '
                    '${_time(sessions[index].session.sessionDate)}',
                  ),
                  _line('المحكمة: ${sessions[index].session.courtLocation}'),
                  _line(
                    'الدائرة: ${_value(sessions[index].session.circleNumber)}',
                  ),
                  _line('القرار: ${_value(sessions[index].session.decision)}'),
                  pw.Divider(color: PdfColors.grey400),
                  pw.SizedBox(height: 8),
                ],
              ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printDailyAgenda(
    List<SessionWithDetails> sessions,
    String title,
    DateTime date,
  ) async {
    await Printing.layoutPdf(
      onLayout: (format) =>
          buildDailyAgenda(sessions, title, date, pageFormat: format),
      name: 'Agenda_${date.year}_${date.month}_${date.day}.pdf',
    );
  }

  static pw.Widget _line(String text, {bool bold = false}) => pw.Text(
    text,
    textAlign: pw.TextAlign.right,
    overflow: pw.TextOverflow.span,
    style: pw.TextStyle(
      fontSize: 12,
      lineSpacing: 3,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  );

  static String _value(String? value) =>
      value == null || value.trim().isEmpty ? 'غير مسجل' : value.trim();

  static String _date(DateTime date) =>
      '${_two(date.day)}/${_two(date.month)}/${date.year}';

  static String _time(DateTime date) =>
      '${_two(date.hour)}:${_two(date.minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
