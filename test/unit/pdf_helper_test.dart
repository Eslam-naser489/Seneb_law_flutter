import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/utils/pdf_helper.dart';

class _RecordingBundle extends CachingAssetBundle {
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) {
    loaded.add(key);
    return rootBundle.load(key);
  }
}

SessionWithDetails _session(int index, {String? decision}) {
  final date = DateTime(2026, 11, 8, 9, 30);
  return SessionWithDetails(
    session: SessionEntity(
      revision: 1,
      createdAt: DateTime(2026),
      id: 'session-$index',
      caseId: 'case-$index',
      sessionDate: date,
      courtLocation: 'محكمة القاهرة الابتدائية',
      circleNumber: 'الدائرة $index',
      decision: decision ?? 'تأجيل الجلسة لتقديم المستندات',
    ),
    caseEntity: CaseEntity(
      revision: 1,
      statusCode: 'ACTIVE',
      id: 'case-$index',
      clientId: 'client-$index',
      caseNumber: '$index لسنة ٢٠٢٦',
      status: 'جارية',
      createdAt: date,
    ),
    client: ClientEntity(
      revision: 1,
      whatsappConsentStatus: 'UNKNOWN',
      id: 'client-$index',
      name: 'موكل تجريبي $index',
      isArchived: false,
      createdAt: date,
    ),
  );
}

int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Arabic agenda loads only bundled fonts with networking disabled',
    () async {
      final bundle = _RecordingBundle();
      final bytes = await HttpOverrides.runZoned(
        () => PdfHelper.buildDailyAgenda(
          [_session(1)],
          'أجندة الجلسات',
          DateTime(2026, 11, 8),
          fontBundle: bundle,
        ),
        createHttpClient: (_) => throw StateError('Network must remain unused'),
      );

      expect(bundle.loaded, [
        PdfHelper.regularFontAsset,
        PdfHelper.boldFontAsset,
      ]);
      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
      expect(latin1.decode(bytes), contains('/FontFile2'));
      expect(_pageCount(bytes), 1);
    },
  );

  test('empty agenda remains a valid one-page offline document', () async {
    final bytes = await PdfHelper.buildDailyAgenda(
      [],
      'أجندة الجلسات',
      DateTime(2026, 11, 8),
    );
    expect(_pageCount(bytes), 1);
  });

  test(
    'long agenda paginates without overflowing or truncating sessions',
    () async {
      final short = await PdfHelper.buildDailyAgenda(
        [_session(1)],
        'أجندة الجلسات',
        DateTime(2026, 11, 8),
      );
      final long = await PdfHelper.buildDailyAgenda(
        List.generate(75, (index) => _session(index + 1)),
        'أجندة الجلسات',
        DateTime(2026, 11, 8),
      );
      expect(_pageCount(long), greaterThan(1));
      expect(long.length, greaterThan(short.length));
      if (const bool.fromEnvironment('WRITE_SPRINT0_ARTIFACTS')) {
        await Directory('.dart_tool/sprint0').create(recursive: true);
        await File('.dart_tool/sprint0/agenda.pdf').writeAsBytes(long);
      }
    },
  );

  test(
    'an individual long decision spans pages instead of overflowing',
    () async {
      final bytes = await PdfHelper.buildDailyAgenda(
        [
          _session(
            1,
            decision: List.filled(250, 'قرار تجريبي طويل للمراجعة').join('\n'),
          ),
        ],
        'أجندة الجلسات',
        DateTime(2026, 11, 8),
      );
      expect(_pageCount(bytes), greaterThan(1));
    },
  );
}
