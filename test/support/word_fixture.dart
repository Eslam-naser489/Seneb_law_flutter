import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// بيانات اصطناعية فقط؛ لا يحتوي المستودع ملفات Word فعلية.
Uint8List wordFixture({String? body, Map<String, String> extra = const {}}) {
  const ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final parts = <String, String>{
    '[Content_Types].xml':
        '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>''',
    '_rels/.rels':
        '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''',
    'word/_rels/document.xml.rels':
        '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/><Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>''',
    'word/document.xml':
        '''<w:document xmlns:w="$ns" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>${body ?? '''
<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t>مستند اختبار توليد البيانات</w:t></w:r></w:p>
<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>هذه بيانات اصطناعية لفحص العربية والحقول ولا تمثل عقدًا قانونيًا.</w:t></w:r></w:p>
<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>الموكل: {{cli</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>ent_na</w:t></w:r><w:r><w:t>me}} — {{client_name}}</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:bidiVisual/><w:tblW w:w="9000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="4500"/><w:gridCol w:w="4500"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>القضية {{case_number}}</w:t></w:r></w:p></w:tc><w:tc><w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>{{custom_value}}</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
'''}<w:sectPr><w:headerReference w:type="default" r:id="rIdHeader"/><w:footerReference w:type="default" r:id="rIdFooter"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/></w:sectPr></w:body></w:document>''',
    'word/header1.xml':
        '<w:hdr xmlns:w="$ns"><w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>مكتب اختباري — {{client_name}}</w:t></w:r></w:p></w:hdr>',
    'word/footer1.xml':
        '<w:ftr xmlns:w="$ns"><w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>مرجع {{case_number}} — صفحة </w:t></w:r><w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>',
    ...extra,
  };
  // رقم الصفحة في فقرة منفصلة عن الحقول القابلة للاستبدال.
  parts['word/footer1.xml'] = parts['word/footer1.xml']!.replaceFirst(
    ' — صفحة </w:t></w:r>',
    '</w:t></w:r></w:p><w:p><w:r><w:t>صفحة </w:t></w:r>',
  );
  final archive = Archive();
  for (final e in parts.entries) {
    final bytes = utf8.encode(e.value);
    archive.add(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
