import 'dart:typed_data';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/features/reports/domain/report_models.dart';
import 'package:seneb_law/features/reports/data/report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late OfficeAccess access;
  late ScopedAppRepository repo;
  late String client, caseId;
  final pdf = Uint8List.fromList('%PDF-test'.codeUnits);
  test('report PDF renders long Arabic content offline', () async {
    final prepared = await repo.prepareReport(
      ReportRequest(
        clientId: client,
        caseId: caseId,
        sections: {
          'summary': List.filled(
            35,
            'تقرير اختباري: تم تقديم المستندات ومراجعة إجراءات القضية.',
          ).join('\n'),
        },
      ),
    );
    final bytes = await ReportPdf.build(prepared);
    expect(bytes.take(5).toList(), '%PDF-'.codeUnits);
    if (const bool.fromEnvironment('WRITE_SPRINT3_ARTIFACTS')) {
      final output = File('.dart_tool/sprint3/report.pdf');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes);
    }
  });
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    access = OfficeAccess(AppRepository(db));
    await access.bootstrapOwner('اختبار', '481637');
    await access.signIn((await access.unlockProfiles()).single.id, '481637');
    repo = access.workspace(access.session!);
    client = await repo.addClient(name: 'موكل اصطناعي');
    caseId = await repo.addCase(clientId: client, caseNumber: '123');
  });
  tearDown(() async {
    access.dispose();
    await db.close();
  });
  Future<PreparedReport> prepare() => repo.prepareReport(
    ReportRequest(
      clientId: client,
      caseId: caseId,
      sections: {'summary': 'نص مراجع'},
    ),
  );
  test(
    'snapshot excludes finance by default and survives branding changes',
    () async {
      final preview = await prepare();
      final saved = await repo.finalizeReport(
        preview,
        pdf,
        operationKey: 'once',
      );
      await repo.saveReportBranding('اسم جديد', null);
      final old = await repo.readReport(saved.report.id);
      expect(old.report.snapshotJson, preview.snapshotJson);
      expect(old.report.includesFinance, isFalse);
      expect(old.report.textContent, isNot(contains('اسم جديد')));
      await expectLater(
        db.customStatement('DELETE FROM case_reports'),
        throwsA(anything),
      );
    },
  );
  test('changed sources invalidate preview', () async {
    final preview = await prepare();
    await repo.saveReportBranding('تعديل', null);
    await expectLater(
      repo.finalizeReport(preview, pdf, operationKey: 'stale'),
      throwsA(anything),
    );
    expect(await db.select(db.caseReports).get(), isEmpty);
  });
  test('sharing requires review and WhatsApp consent', () async {
    final saved = await repo.finalizeReport(
      await prepare(),
      pdf,
      operationKey: 'saved',
    );
    for (final channel in ['NATIVE', 'WHATSAPP']) {
      await expectLater(
        repo.beginShare(
          saved.report.id,
          expectedHash: saved.report.contentHash,
          recipient: '',
          channel: channel,
          format: 'TEXT',
          reviewed: channel == 'WHATSAPP',
        ),
        throwsA(anything),
      );
    }
    expect(await db.select(db.shareAttempts).get(), isEmpty);
  });
  test('cancelled attempts cannot be confirmed as sent', () async {
    final saved = await repo.finalizeReport(
      await prepare(),
      pdf,
      operationKey: 'saved',
    );
    final id = await repo.beginShare(
      saved.report.id,
      expectedHash: saved.report.contentHash,
      recipient: '',
      channel: 'NATIVE',
      format: 'TEXT',
      reviewed: true,
    );
    await repo.finishShare(id, 'CANCELLED');
    await expectLater(repo.confirmReportSent(id), throwsA(anything));
    expect(
      (await repo.shareHistory(saved.report.id)).single.status,
      'CANCELLED',
    );
  });
  test(
    'WhatsApp recipient normalization rejects local and malformed numbers',
    () {
      expect(normalizedRecipient('+٢٠١٠١٢٣٤٥٦٧٨'), '201012345678');
      expect(() => normalizedRecipient('01012345678'), throwsFormatException);
      expect(
        whatsappDraftUri('+201012345678', 'نص & خاص').queryParameters['text'],
        'نص & خاص',
      );
    },
  );
}
