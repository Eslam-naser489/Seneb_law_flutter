import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:seneb_law/core/database/app_repository.dart';

class PdfHelper {
  // دالة لطباعة أو حفظ أجندة الجلسات
  static Future<void> printDailyAgenda(
      List<SessionWithDetails> sessions, String title, DateTime date) async {
    final pdf = pw.Document();

    // تحميل خط عربي مدعوم من Google Fonts عشان الحروف متطلعش متقطعة
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicFontBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl, // اتجاه الكتابة عربي
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // الهيدر
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'الموافق: ${date.year}-${date.month}-${date.day}',
                  style: const pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 2, color: PdfColors.indigo900),
              pw.SizedBox(height: 20),

              // لو مفيش جلسات
              if (sessions.isEmpty)
                pw.Center(
                  child: pw.Text('لا توجد جلسات مسجلة في هذا اليوم.', style: const pw.TextStyle(fontSize: 18)),
                )
              else
                // قائمة الجلسات
                pw.ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final item = sessions[index];
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 12),
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('الموكل: ${item.client.name}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                              pw.Text('القضية: ${item.caseEntity.caseNumber}', style: const pw.TextStyle(fontSize: 14)),
                            ],
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text('المحكمة / الدائرة: ${item.session.courtLocation}', style: const pw.TextStyle(fontSize: 14)),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );

    // أمر الطباعة (بيفتح نافذة الطباعة أو حفظ كـ PDF في الويندوز/الأندرويد)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Agenda_${date.year}_${date.month}_${date.day}.pdf',
    );
  }
}