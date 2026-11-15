import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/database/database.dart';
import '../../../core/utils/pdf_helper.dart';
import '../domain/finance_models.dart';

class FinancePdf {
  static Future<Uint8List> receipt(FinancialReceipt receipt) async {
    final data = jsonDecode(receipt.snapshotJson) as Map<String, dynamic>;
    final e = data['entry'] as Map<String, dynamic>;
    final title = e['kind'] == 'REFUND' ? 'إيصال رد مبلغ' : 'إيصال استلام مبلغ';
    return _document('$title رقم ${receipt.number}', [
      if (receipt.voidedAt != null) 'ملغى — ${receipt.voidReason}',
      'تاريخ الإصدار: ${_date(receipt.createdAt)}',
      'تاريخ الحركة: ${_date(ClientLedgerEntry.fromJson(e).occurredAt)}',
      'الموكل: ${data['clientName']}',
      if (data['caseNumber'] != null) 'القضية: ${data['caseNumber']}',
      'المبلغ: ${moneyText(e['amountMinor'] as int)}',
      'طريقة الدفع: ${methodLabels[e['paymentMethod']] ?? ''}',
      'البيان: ${e['description']}',
      'المُصدر: ${data['issuer']}',
      'توقيع المستلم: ____________________',
    ]);
  }

  static Future<Uint8List> statement(
    ClientAccount account, {
    DateTime? from,
    DateTime? through,
    String? caseNumber,
  }) async {
    if (from != null && through != null && from.isAfter(through)) {
      throw const FormatException('راجع نطاق تاريخ الكشف.');
    }
    final end = through == null
        ? null
        : DateTime(through.year, through.month, through.day + 1);
    final active = account.entries.where((e) => e.voidedAt == null);
    var balance = from == null
        ? 0
        : checkedSum(
            active
                .where((e) => e.occurredAt.isBefore(from))
                .map((e) => ledgerEffect(e.kind, e.amountMinor)),
          );
    final lines = <String>[
      'أُعد في ${_date(DateTime.now())}؛ يعكس القيود السارية وقت إعداده.',
      'الموكل: ${account.client.name}',
      if (caseNumber != null) 'القضية: $caseNumber',
      'الفترة: ${from == null ? 'من البداية' : _date(from)} - ${through == null ? 'حتى الآن' : _date(through)}',
      'رصيد افتتاحي: ${moneyText(balance)}',
    ];
    final selected = active.where(
      (e) =>
          (from == null || !e.occurredAt.isBefore(from)) &&
          (end == null || e.occurredAt.isBefore(end)),
    );
    for (final e in selected) {
      balance = checkedSum([balance, ledgerEffect(e.kind, e.amountMinor)]);
      lines.add(
        '${_date(e.occurredAt)} | ${ledgerLabels[e.kind]} | ${moneyText(e.amountMinor)}\n${e.description}\nالرصيد: ${moneyText(balance)}',
      );
    }
    if (selected.isEmpty) lines.add('لا توجد حركات خلال الفترة.');
    lines.add('الرصيد الختامي: ${moneyText(balance)}');
    lines.add(
      balance < 0
          ? 'رصيد دائن لصالح الموكل.'
          : 'الرصيد الموجب مستحق على الموكل.',
    );
    return _document('كشف حساب الموكل', lines);
  }

  static Future<Uint8List> _document(String title, List<String> lines) async {
    final regular = pw.Font.ttf(
      await rootBundle.load(PdfHelper.regularFontAsset),
    );
    final bold = pw.Font.ttf(await rootBundle.load(PdfHelper.boldFontAsset));
    final pdf = pw.Document(title: title);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.all(36),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
          ],
        ),
        footer: (c) => pw.Text(
          'صفحة ${c.pageNumber} من ${c.pagesCount}',
          textAlign: pw.TextAlign.center,
        ),
        build: (_) => [
          for (final line in lines) ...[
            pw.NewPage(freeSpace: 80),
            pw.Text(
              line,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
            ),
            pw.SizedBox(height: 12),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
