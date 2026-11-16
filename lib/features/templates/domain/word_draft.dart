import 'dart:convert';
import '../../../core/database/database.dart';

const wordFieldLabels = {
  'client_name': 'اسم الموكل',
  'client_national_id': 'الرقم القومي — حساس',
  'client_phone': 'هاتف الموكل',
  'client_address': 'عنوان الموكل',
  'case_number': 'رقم القضية',
  'opponent_name': 'اسم الخصم',
  'lawyer_name': 'اسم المحامي',
};

class WordDraft {
  WordDraft({
    required this.templateId,
    required this.clientId,
    this.caseId,
    required Map<String, String> values,
    required this.sourceHash,
  }) : inputJson = jsonEncode(values);
  final String templateId, clientId, sourceHash, inputJson;
  final String? caseId;
  Map<String, String> get values =>
      Map<String, String>.from(jsonDecode(inputJson) as Map);
}

class WordContext {
  const WordContext(this.template, this.values);
  final WordTemplate template;
  final Map<String, String> values;
}
