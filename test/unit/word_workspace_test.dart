import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/backup_service.dart';
import 'package:seneb_law/features/lawyers/domain/office_models.dart';
import 'package:seneb_law/features/templates/domain/word_draft.dart';
import '../support/word_fixture.dart';

void main() {
  late AppDatabase db;
  late OfficeAccess access;
  late ScopedAppRepository repo;
  late Directory root;
  late String client, caseId, template;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('seneb-word-test-');
    db = AppDatabase.forTesting(
      NativeDatabase(File(p.join(root.path, 'seneb_law_db.sqlite'))),
    );
    access = OfficeAccess(AppRepository(db, storageRoot: root));
    await access.bootstrapOwner('مالك اختباري', '481637');
    await access.signIn((await access.unlockProfiles()).single.id, '481637');
    repo = access.workspace(access.session!);
    client = await repo.addClient(name: 'موكل أصلي');
    caseId = await repo.addCase(clientId: client, caseNumber: '123');
    template = await repo.importWordTemplate(
      'قالب اختباري',
      'عقود',
      wordFixture(),
    );
  });
  tearDown(() async {
    access.dispose();
    await db.close();
    await root.delete(recursive: true);
  });
  Future<WordDraft> draft() => repo.prepareWord(
    template,
    client,
    caseId: caseId,
    values: {
      'client_name': 'اسم للمستند فقط',
      'case_number': '123',
      'custom_value': 'اختبار',
    },
    sensitiveReviewed: false,
  );

  test(
    'immutable version, overrides, duplicate retries and sharing review',
    () async {
      final input = await draft();
      final doc = await repo.finalizeWord(
        input,
        operationKey: 'one',
        reviewed: true,
      );
      expect(
        (await repo.finalizeWord(
          input,
          operationKey: 'one',
          reviewed: true,
        )).id,
        doc.id,
      );
      expect((await repo.clientProfile(client)).client.name, 'موكل أصلي');
      expect(await repo.wordDocuments(client), hasLength(1));
      await expectLater(
        db.customStatement('DELETE FROM word_documents'),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement("UPDATE word_templates SET name='changed'"),
        throwsA(anything),
      );
      final version2 = await repo.importWordTemplate(
        'قالب اختباري',
        'صياغات',
        wordFixture(),
      );
      expect(version2, isNot(template));
      expect((await repo.wordTemplates()).first.version, 2);
      expect((await repo.readWordDocument(doc.id)).templateId, template);
      await expectLater(
        repo.beginWordHandoff(
          doc.id,
          'NATIVE',
          checksum: doc.checksum,
          reviewed: false,
        ),
        throwsA(anything),
      );
      final a = await repo.beginWordHandoff(
        doc.id,
        'NATIVE',
        checksum: doc.checksum,
        reviewed: true,
      );
      await repo.finishWordHandoff(a, 'CANCELLED');
      expect((await repo.wordShareHistory(doc.id)).single.status, 'CANCELLED');
      await expectLater(repo.finishWordHandoff(a, 'OPENED'), throwsA(anything));
    },
  );
  test(
    'source change invalidates draft and audit failure rolls back without false success',
    () async {
      final input = await draft();
      await db.customStatement(
        'UPDATE clients SET revision=revision+1 WHERE id=?',
        [client],
      );
      await expectLater(
        repo.finalizeWord(input, operationKey: 'stale', reviewed: true),
        throwsA(anything),
      );
      final fresh = await draft();
      await db.customStatement(
        "CREATE TRIGGER reject_word_audit BEFORE INSERT ON audit_log WHEN NEW.entity_type='WORD_DOCUMENT' BEGIN SELECT RAISE(ABORT,'test failure'); END",
      );
      await expectLater(
        repo.finalizeWord(fresh, operationKey: 'retry', reviewed: true),
        throwsA(anything),
      );
      expect(await repo.wordDocuments(client), isEmpty);
      await db.customStatement('DROP TRIGGER reject_word_audit');
      await repo.finalizeWord(fresh, operationKey: 'retry', reviewed: true);
      expect(await repo.wordDocuments(client), hasLength(1));
    },
  );
  test(
    'sensitive data, mismatched case and case-only permissions are enforced',
    () async {
      final sensitive = await repo.importWordTemplate(
        'حساس',
        'اختبار',
        wordFixture(
          body: '<w:p><w:r><w:t>{{client_national_id}}</w:t></w:r></w:p>',
        ),
      );
      await expectLater(
        repo.prepareWord(
          sensitive,
          client,
          values: {
            'client_name': 'x',
            'case_number': '1',
            'client_national_id': 'synthetic',
          },
          sensitiveReviewed: false,
        ),
        throwsA(anything),
      );
      final other = await repo.addClient(name: 'آخر');
      await expectLater(
        repo.wordContext(template, other, caseId: caseId),
        throwsA(anything),
      );
      final doc = await repo.finalizeWord(
        await draft(),
        operationKey: 'private',
        reviewed: true,
      );
      final lawyer = await repo.saveStaff(
        const StaffInput(name: 'محامٍ', role: OfficeRole.lawyer),
        initialPin: '671293',
      );
      await repo.assign(
        caseId,
        lawyer,
        forCase: true,
        role: 'LEAD',
        reason: 'اختبار',
      );
      await access.signIn(lawyer, '671293');
      await access.changeTemporaryPin(access.session!, '906245');
      await access.signIn(lawyer, '906245');
      final scoped = access.workspace(access.session!);
      await expectLater(scoped.readWordDocument(doc.id), throwsA(anything));
      await expectLater(
        scoped.wordContext(template, client, caseId: caseId),
        throwsA(anything),
      );
      await expectLater(
        scoped.importWordTemplate('غير مسموح', 'اختبار', wordFixture()),
        throwsA(anything),
      );
      await expectLater(repo.readWordDocument(doc.id), throwsA(anything));
    },
  );
  test(
    'database backup restore preserves template and exact generated bytes after restart',
    () async {
      final doc = await repo.finalizeWord(
        await draft(),
        operationKey: 'durable',
        reviewed: true,
      );
      final backup = await BackupService().create(
        databaseFile: File(p.join(root.path, 'seneb_law_db.sqlite')),
        storageRoot: root,
        destinationRoot: Directory(p.join(root.path, 'backups')),
      );
      final restored = await BackupService().restoreIsolated(
        backup: backup.directory,
        destination: Directory(p.join(root.path, 'restore')),
      );
      final reopened = AppDatabase.openAt(restored);
      try {
        expect(
          (await reopened.select(reopened.wordDocuments).get()).single.bytes,
          doc.bytes,
        );
        expect(
          (await reopened.select(reopened.wordTemplates).get()).single.id,
          template,
        );
      } finally {
        await reopened.close();
      }
    },
  );
}
