import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class TemplateFailure implements Exception {
  const TemplateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// نطاق مقصود: نصوص وفقرات وجداول ورؤوس وتذييلات، دون محتوى نشط.
class DocxEngine {
  static const maxBytes = 10 * 1024 * 1024;
  static const wordNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static final token = RegExp(r'\{\{([a-z][a-z0-9_]{0,63})\}\}');
  static bool _part(String name) =>
      RegExp(r'^word/(document|header\d*|footer\d*)\.xml$').hasMatch(name);
  static Never _fail(String message) => throw TemplateFailure(message);

  static Archive _read(Uint8List bytes) {
    if (bytes.length > maxBytes || bytes.length < 22) {
      _fail('اختر DOCX سليمًا لا يتجاوز 10 ميجابايت.');
    }
    // نفحص الدليل قبل فك الضغط، ونرفض ZIP64 والملفات المشفرة والضخمة.
    final d = ByteData.sublistView(bytes);
    var end = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (d.getUint32(i, Endian.little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) _fail('الملف ليس حزمة DOCX سليمة.');
    final count = d.getUint16(end + 10, Endian.little);
    var offset = d.getUint32(end + 16, Endian.little);
    if (count == 0 || count > 500 || d.getUint16(end + 4, Endian.little) != 0) {
      _fail('الحزمة متعددة الأجزاء أو كبيرة جدًا؛ احفظ قالبًا مبسطًا.');
    }
    var total = 0;
    final names = <String>{};
    for (var i = 0; i < count; i++) {
      if (offset + 46 > end ||
          d.getUint32(offset, Endian.little) != 0x02014b50) {
        _fail('دليل DOCX تالف.');
      }
      final size = d.getUint32(offset + 24, Endian.little);
      total += size;
      final length = d.getUint16(offset + 28, Endian.little);
      if (size > maxBytes ||
          total > 30 * 1024 * 1024 ||
          offset + 46 + length > end ||
          (d.getUint16(offset + 8, Endian.little) & 1) != 0) {
        _fail('القالب مشفر أو يتجاوز حدود الحجم بعد فك الضغط.');
      }
      final name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + length),
      );
      if (!names.add(name) ||
          name.startsWith('/') ||
          name.contains('..') ||
          name.contains('\\') ||
          name.contains(':')) {
        _fail('مسارات غير آمنة أو مكررة داخل القالب.');
      }
      offset +=
          46 +
          length +
          d.getUint16(offset + 30, Endian.little) +
          d.getUint16(offset + 32, Endian.little);
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (file.isSymbolicLink ||
          name.contains('vbaproject') ||
          name.startsWith('word/embeddings/') ||
          name.startsWith('customxml/') ||
          name.startsWith('_xmlsignatures/')) {
        _fail(
          'القالب يحتوي ماكرو أو كائنًا مضمنًا أو XML مخصصًا أو توقيعًا؛ استخدم نسخة DOCX نصية.',
        );
      }
      if (!file.isFile) continue;
      if (file.size > maxBytes) _fail('جزء من القالب يتجاوز حد الحجم.');
      if (name.endsWith('.xml') || name.endsWith('.rels')) {
        final xml = _xml(file);
        for (final e in xml.descendants.whereType<XmlElement>()) {
          if (e.name.local == 'Relationship' &&
              e.getAttribute('TargetMode') == 'External') {
            _fail(
              'القالب يحتوي روابط خارجية؛ ضمّن الصور وأزل الروابط الخارجية أولًا.',
            );
          }
          if (e.name.namespaceUri == wordNs &&
              [
                'ins',
                'del',
                'sdt',
                'altChunk',
                'object',
                'txbxContent',
              ].contains(e.name.local)) {
            _fail(
              'يوجد تعقب تغييرات أو عنصر تحكم أو مربع نص غير مدعوم؛ حوّله إلى نص عادي في نسخة من القالب.',
            );
          }
          if (e.name.namespaceUri == wordNs &&
              e.name.local == 'instrText' &&
              !RegExp(r'^\s*(PAGE|NUMPAGES)\s*$').hasMatch(e.innerText)) {
            _fail(
              'حقول Word الديناميكية غير مدعومة عدا ترقيم الصفحات؛ حوّلها إلى نص.',
            );
          }
        }
        if (!_part(file.name) &&
            (xml.innerText.contains('{{') || xml.innerText.contains('}}'))) {
          _fail('يوجد حقل خارج المتن والجداول والرؤوس والتذييلات المدعومة.');
        }
      }
    }
    if (archive.findFile('word/document.xml') == null ||
        archive.findFile('[Content_Types].xml') == null ||
        archive.findFile('_rels/.rels') == null) {
      _fail('ملف DOCX يفتقد الأجزاء الأساسية.');
    }
    final types = utf8.decode(archive.findFile('[Content_Types].xml')!.content);
    if (!types.contains(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
        ) ||
        types.toLowerCase().contains('macroenabled')) {
      _fail('اختر DOCX عاديًا دون ماكرو.');
    }
    return archive;
  }

  static XmlDocument _xml(ArchiveFile file) {
    final text = utf8.decode(file.content);
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY'))
      _fail('تعريفات XML الخارجية غير مدعومة.');
    return XmlDocument.parse(text);
  }

  static Iterable<XmlElement> _paragraphs(XmlDocument xml) => xml.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'p' && e.name.namespaceUri == wordNs);
  static List<XmlElement> _texts(XmlElement p) => p.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 't' && e.name.namespaceUri == wordNs)
      .toList();

  static Set<String> inspect(Uint8List bytes) {
    try {
      final fields = <String>{};
      for (final file in _read(bytes).where((f) => _part(f.name))) {
        for (final p in _paragraphs(_xml(file))) {
          final text = _texts(p).map((e) => e.innerText).join();
          final matches = token.allMatches(text);
          final rest = text.replaceAll(token, '');
          if (rest.contains('{{') || rest.contains('}}'))
            _fail(
              'حقل غير صالح أو ممتد بين فقرات؛ استخدم {{field_name}} داخل فقرة واحدة.',
            );
          if (matches.isNotEmpty &&
              p.descendants.whereType<XmlElement>().any(
                (e) => [
                  'tab',
                  'br',
                  'fldChar',
                  'fldSimple',
                  'hyperlink',
                ].contains(e.name.local),
              )) {
            _fail(
              'انقل الحقول إلى فقرة دون تبويبات أو فواصل أو روابط أو حقول Word.',
            );
          }
          fields.addAll(matches.map((m) => m[1]!));
        }
      }
      if (fields.isEmpty)
        _fail('لم توجد حقول؛ أضف {{client_name}} أو حقلًا مخصصًا.');
      if (fields.length > 80) _fail('الحد الأقصى 80 حقلًا.');
      return fields;
    } on TemplateFailure {
      rethrow;
    } catch (_) {
      _fail('تعذر قراءة DOCX؛ أعد حفظه دون تشفير أو محتوى تالف.');
    }
  }

  static Uint8List generate(Uint8List bytes, Map<String, String> values) {
    final fields = inspect(bytes);
    for (final key in fields) {
      final value = values[key] ?? '';
      if (value.trim().isEmpty) _fail('أكمل الحقل المطلوب: {{$key}}.');
      if (value.length > 5000 ||
          RegExp(r'[\x00-\x1F]').hasMatch(value) ||
          value.contains('{{') ||
          value.contains('}}')) {
        _fail(
          'قيمة الحقل $key غير صالحة؛ استخدم نصًا في سطر واحد دون علامات حقول.',
        );
      }
    }
    final output = Archive();
    for (final file in _read(bytes)) {
      if (!_part(file.name)) {
        output.add(file);
        continue;
      }
      final xml = _xml(file);
      for (final p in _paragraphs(xml)) {
        final nodes = _texts(p);
        final text = nodes.map((e) => e.innerText).join();
        for (final match in token.allMatches(text).toList().reversed) {
          var position = 0;
          var inserted = false;
          for (final node in nodes) {
            final old = node.innerText;
            final start = position;
            position += old.length;
            if (start >= match.end || position <= match.start) continue;
            final from = (match.start - start).clamp(0, old.length);
            final to = (match.end - start).clamp(0, old.length);
            node.innerText =
                old.substring(0, from) +
                (inserted ? '' : values[match[1]!]!) +
                old.substring(to);
            node.setAttribute('xml:space', 'preserve');
            inserted = true;
          }
        }
      }
      final data = utf8.encode(xml.toXmlString());
      output.add(ArchiveFile(file.name, data.length, data));
    }
    return Uint8List.fromList(ZipEncoder().encode(output));
  }
}
