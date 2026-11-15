import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../../core/database/database.dart';

const reportSectionLabels = <String, String>{
  'summary': 'ملخص القضية',
  'development': 'آخر تطور أو قرار',
  'nextSession': 'الجلسة القادمة',
  'requirements': 'المطلوب من الموكل',
  'finance': 'الموقف المالي',
  'note': 'ملاحظة المحامي',
};
const shareStatusLabels = <String, String>{
  'STARTED': 'بدأت المحاولة؛ النتيجة غير مسجلة',
  'OPENED': 'فُتحت المشاركة أو المسودة؛ الوصول غير مؤكد',
  'CANCELLED': 'أُلغيت المشاركة',
  'FAILED': 'تعذرت المشاركة',
  'UNAVAILABLE': 'نتيجة المشاركة غير متاحة',
  'SAVED': 'حُفظ الملف',
  'COPIED': 'نُسخ النص',
};
String reportHash(List<int> bytes) => sha256.convert(bytes).toString();
String jsonHash(Object value) => reportHash(utf8.encode(jsonEncode(value)));
String reportDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class ReportRequest {
  ReportRequest({
    required this.clientId,
    this.caseId,
    this.kind = 'REPORT',
    Map<String, String> sections = const {},
    this.includeFinance = false,
    this.receiptNumber,
    this.from,
    this.through,
  }) : sections = Map.unmodifiable(sections);
  final String clientId, kind;
  final String? caseId;
  final Map<String, String> sections;
  final bool includeFinance;
  final int? receiptNumber;
  final DateTime? from, through;
}

class ReportContext {
  ReportContext({
    required this.clientId,
    required this.caseId,
    required this.clientName,
    required this.defaults,
    required this.eligibleNotes,
    required this.financeAllowed,
    required this.recipient,
    required this.consent,
  });
  final String clientId, caseId, clientName, recipient, consent;
  final Map<String, String> defaults;
  final List<CaseNoteEntity> eligibleNotes;
  final bool financeAllowed;
}

class PreparedReport {
  PreparedReport({
    required this.request,
    required this.createdAt,
    required this.sourceHash,
    required Map<String, dynamic> snapshot,
  }) : snapshotJson = jsonEncode(snapshot);
  final ReportRequest request;
  final DateTime createdAt;
  final String sourceHash, snapshotJson;
  Map<String, dynamic> get snapshot =>
      jsonDecode(snapshotJson) as Map<String, dynamic>;
  String get hash => reportHash(utf8.encode(snapshotJson));
  String get text => snapshotText(snapshot);
}

String snapshotText(Map<String, dynamic> s) => <String>[
  s['officeName'] as String,
  s['title'] as String,
  'الموكل: ${s['clientName']}',
  if (s['caseNumber'] != null) 'القضية: ${s['caseNumber']}',
  'تاريخ الإعداد: ${s['date']}',
  for (final section in (s['sections'] as List))
    '${section['label']}\n${section['text']}',
  'المحامي: ${s['lawyerName']}',
  if ((s['lawyerPhone'] as String).isNotEmpty)
    'هاتف المكتب / المحامي: ${s['lawyerPhone']}',
].join('\n\n');

class ReportBundle {
  const ReportBundle(this.report, this.artifacts);
  final CaseReport report;
  final List<GeneratedDocument> artifacts;
  Uint8List get pdf => artifacts.singleWhere((a) => a.format == 'PDF').bytes;
  List<Uint8List> get images =>
      artifacts.where((a) => a.format == 'PNG').map((a) => a.bytes).toList();
}

String normalizedRecipient(String input) {
  var s = input.trim();
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i').replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  s = s.replaceAll(RegExp(r'[\s()\-]'), '');
  if (s.startsWith('+')) s = s.substring(1);
  if (s.startsWith('00')) s = s.substring(2);
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(s)) {
    throw const FormatException(
      'راجع رقم واتساب بصيغة دولية؛ مثال: +201012345678.',
    );
  }
  return s;
}

Uri whatsappDraftUri(String recipient, String text, {bool web = false}) => web
    ? Uri.https('web.whatsapp.com', '/send', {
        'phone': normalizedRecipient(recipient),
        'text': text,
      })
    : Uri.https('wa.me', '/${normalizedRecipient(recipient)}', {'text': text});
