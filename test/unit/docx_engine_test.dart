import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:seneb_law/features/templates/domain/docx_engine.dart';
import '../support/word_fixture.dart';

void main() {
  final values = {
    'client_name': 'موكل تجريبي & <Test>',
    'case_number': '١٢٣ / 2026',
    'custom_value': 'نص مختلط ABC ۱۲۳',
  };
  test(
    'split runs, repeated tokens, tables, headers, footers preserve XML and RTL',
    () async {
      final original = wordFixture();
      expect(DocxEngine.inspect(original), values.keys.toSet());
      final output = DocxEngine.generate(original, values);
      final zip = ZipDecoder().decodeBytes(output, verify: true);
      final xml = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content),
      );
      expect(xml.innerText, contains(values['client_name']));
      expect(xml.innerText, contains(values['custom_value']));
      expect(xml.findAllElements('w:bidi'), isNotEmpty);
      expect(xml.findAllElements('w:b'), isNotEmpty);
      for (final part in [
        'word/document.xml',
        'word/header1.xml',
        'word/footer1.xml',
      ]) {
        final text = XmlDocument.parse(
          utf8.decode(zip.findFile(part)!.content),
        ).innerText;
        expect(text, isNot(contains('{{')));
      }
      expect(
        zip.findFile('word/_rels/document.xml.rels')!.content,
        ZipDecoder()
            .decodeBytes(original)
            .findFile('word/_rels/document.xml.rels')!
            .content,
      );
      if (const bool.fromEnvironment('WRITE_SPRINT4_ARTIFACTS')) {
        final file = File('.dart_tool/sprint4/generated.docx');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(output);
      }
    },
  );
  test(
    'missing, malformed, crossing paragraphs and invalid input block generation',
    () {
      expect(
        () => DocxEngine.generate(wordFixture(), {}),
        throwsA(isA<TemplateFailure>()),
      );
      expect(
        () => DocxEngine.generate(wordFixture(), {
          ...values,
          'custom_value': '{{oops}}',
        }),
        throwsA(isA<TemplateFailure>()),
      );
      expect(
        () => DocxEngine.inspect(
          wordFixture(
            body:
                '<w:p><w:r><w:t>{{client_</w:t></w:r></w:p><w:p><w:r><w:t>name}}</w:t></w:r></w:p>',
          ),
        ),
        throwsA(isA<TemplateFailure>()),
      );
    },
  );
  test(
    'active content, tracked changes, external links and unsafe ZIP paths rejected',
    () {
      for (final extra in [
        {'word/vbaProject.bin': 'macro'},
        {'../escape.xml': '<x/>'},
        {
          'word/_rels/image.rels':
              '<Relationships><Relationship TargetMode="External" Target="https://example.invalid/"/></Relationships>',
        },
        {'customXml/item1.xml': '<x/>'},
        {'word/settings.xml': '<settings value="{{unsupported}}"/>'},
      ]) {
        expect(
          () => DocxEngine.inspect(wordFixture(extra: extra)),
          throwsA(isA<TemplateFailure>()),
        );
      }
      expect(
        () => DocxEngine.inspect(
          wordFixture(
            body:
                '<w:p><w:ins><w:r><w:t>{{client_name}}</w:t></w:r></w:ins></w:p>',
          ),
        ),
        throwsA(isA<TemplateFailure>()),
      );
      expect(
        () => DocxEngine.inspect(wordFixture(body: '<w:p><w:fldSimple w:instr="INCLUDETEXT remote"><w:r><w:t>نص</w:t></w:r></w:fldSimple></w:p>')),
        throwsA(isA<TemplateFailure>()),
      );
    },
  );
  test(
    'several split fields in same run retain surrounding formatting and text',
    () {
      final bytes = wordFixture(
        body:
            '<w:p><w:r><w:t>قبل {{client_name}} وسط {{case_</w:t></w:r><w:r><w:t>number}} بعد</w:t></w:r></w:p>',
      );
      final xml = XmlDocument.parse(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(DocxEngine.generate(bytes, values))
              .findFile('word/document.xml')!
              .content,
        ),
      );
      expect(
        xml.innerText,
        'قبل ${values['client_name']} وسط ${values['case_number']} بعد',
      );
    },
  );
}
