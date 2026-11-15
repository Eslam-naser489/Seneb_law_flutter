import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as native;

import '../support/v2_fixture.dart';

void main() {
  late Directory temporary;
  late Directory office;
  late File file;
  late File evidence;
  final opened = <AppDatabase>[];

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('seneb-migration-test-');
    office = await Directory(p.join(temporary.path, 'office')).create();
    file = File(p.join(office.path, 'seneb_law_db.sqlite'));
    evidence = await File(
      p.join(temporary.path, 'synthetic-evidence.txt'),
    ).writeAsString('مستند اختبار اصطناعي فقط');
  });

  tearDown(() async {
    for (final db in opened.reversed) {
      await db.close();
    }
    opened.clear();
    // This test creates and owns the exact temporary directory being removed.
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  AppDatabase open(Directory root, {Future<void> Function()? probe}) {
    final db = AppDatabase.openAt(root, migrationProbe: probe);
    opened.add(db);
    return db;
  }

  Future<List<Directory>> backups(Directory root) async =>
      (await Directory(p.join(root.path, 'backups')).list().toList())
          .whereType<Directory>()
          .where((entry) => p.basename(entry.path).startsWith('seneb-backup-'))
          .toList();

  Future<void> close(AppDatabase db) async {
    opened.remove(db);
    await db.close();
  }

  test(
    'populated v2 preserves source rows and stages reviewed conversion only',
    () async {
      final source = createV2Fixture(file, documentPath: evidence.path);
      source.execute(
        'INSERT INTO clients (id, name, is_archived, created_at) VALUES (?, ?, ?, ?)',
        ['other-client', 'موكل آخر للاختبار', 1, 1700000008],
      );
      source.execute('UPDATE transactions SET client_id = ? WHERE id = ?', [
        'other-client',
        'fixture-transaction',
      ]);
      source.execute('UPDATE cases SET status = ? WHERE id = ?', [
        'حالة قديمة مخصصة',
        'fixture-case',
      ]);
      final originalTransaction = Map<String, Object?>.from(
        source.select('SELECT * FROM transactions').single,
      );
      source.close();

      final db = open(office);
      final transaction =
          (await db.customSelect('SELECT * FROM transactions').get())
              .single
              .data;
      expect(transaction, originalTransaction);
      expect(
        (await db.customSelect('PRAGMA user_version').get()).single.data.values,
        [5],
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA foreign_keys').get()).single.data.values,
        [1],
      );

      final reviews = await db.select(db.legacyTransactionReviews).get();
      expect(reviews, hasLength(1));
      final review = reviews.single;
      expect(review.legacyTransactionId, 'fixture-transaction');
      expect(review.sourceAmountText, '1.005');
      expect(review.proposedAmountMinor, 101);
      expect(review.roundingResidual, '-0.005');
      expect(review.hasSubcentPrecision, isTrue);
      expect(review.ownershipMismatch, isTrue);
      expect(review.isNegative, isFalse);
      expect(review.reviewStatus, 'PENDING');
      expect(review.reviewedAt, isNull);
      expect(review.reviewedBy, isNull);

      final assignments = await db.select(db.clientLawyers).get();
      expect(assignments, hasLength(1));
      expect(assignments.single.clientId, 'fixture-client');
      expect(assignments.single.lawyerId, 'fixture-lawyer');
      expect(assignments.single.startedAt, isNull);
      expect(assignments.single.endedAt, isNull);
      expect(await db.select(db.caseLawyers).get(), isEmpty);
      expect(await db.select(db.localCredentials).get(), isEmpty);
      for (final client in await db.select(db.clients).get()) {
        expect(client.whatsappConsentStatus, 'UNKNOWN');
        expect(client.consentRecordedAt, isNull);
      }
      final archived = (await db.select(db.clients).get()).singleWhere(
        (row) => row.id == 'other-client',
      );
      expect(archived.isArchived, isTrue);
      final migratedCase = (await db.select(db.cases).get()).single;
      expect(migratedCase.status, 'حالة قديمة مخصصة');
      expect(migratedCase.statusCode, 'LEGACY');
      expect(migratedCase.createdAt.millisecondsSinceEpoch, 1700000001000);
      expect(
        (await db.select(db.caseNotes).get()).single.visibility,
        'INTERNAL',
      );
      final session = (await db.select(db.sessions).get()).single;
      expect(session.circleNumber, '١٢');
      expect(session.decision, 'قرار تجريبي');
      expect(
        (await db.select(db.caseDocuments).get()).single.id,
        'fixture-document',
      );

      final savedBackups = await backups(office);
      expect(savedBackups, hasLength(1));
      final manifest = await BackupService().validate(savedBackups.single);
      expect(manifest['schemaVersion'], 2);
      final snapshot = native.sqlite3.open(
        p.join(savedBackups.single.path, 'database.sqlite'),
        mode: native.OpenMode.readOnly,
      );
      try {
        expect(
          Map<String, Object?>.from(
            snapshot.select('SELECT * FROM transactions').single,
          ),
          originalTransaction,
        );
      } finally {
        snapshot.close();
      }

      await close(db);
      final reopened = open(office);
      expect(
        await reopened.select(reopened.legacyTransactionReviews).get(),
        hasLength(1),
      );
      expect(await reopened.select(reopened.clientLawyers).get(), hasLength(1));
      expect(
        (await reopened.select(reopened.auditLog).get()).map((e) => e.action),
        ['UPGRADE_V2_V3', 'UPGRADE_V3_V4', 'UPGRADE_V4_V5'],
      );
      expect(await backups(office), hasLength(1));
    },
  );

  test(
    'empty v2 upgrades without inventing assignments, money, or credentials',
    () async {
      createV2Fixture(file, populate: false).close();
      final db = open(office);
      expect(await db.select(db.clients).get(), isEmpty);
      expect(await db.select(db.clientLawyers).get(), isEmpty);
      expect(await db.select(db.caseLawyers).get(), isEmpty);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.legacyTransactionReviews).get(), isEmpty);
      expect(await db.select(db.localCredentials).get(), isEmpty);
      expect(
        (await db.select(db.auditLog).get())
            .firstWhere((e) => e.action == 'UPGRADE_V2_V3')
            .actorKind,
        'MIGRATION',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(await backups(office), hasLength(1));
    },
  );

  test(
    'failed upgrade rolls back and validated v2 backup restores and upgrades',
    () async {
      createV2Fixture(file, documentPath: evidence.path).close();
      var reachedProbe = false;
      final failed = open(
        office,
        probe: () async {
          reachedProbe = true;
          throw StateError('Injected failure after schema and data changes');
        },
      );
      await expectLater(failed.select(failed.clients).get(), throwsA(anything));
      expect(reachedProbe, isTrue);
      await close(failed);

      final original = native.sqlite3.open(
        file.path,
        mode: native.OpenMode.readOnly,
      );
      try {
        expect(original.userVersion, 2);
        expect(
          original.select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='legacy_transaction_reviews'",
          ),
          isEmpty,
        );
        expect(
          original.select('SELECT amount FROM transactions').single['amount'],
          1.005,
        );
        expect(
          original.select('SELECT id FROM clients').single['id'],
          'fixture-client',
        );
        expect(original.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        original.close();
      }
      final saved = (await backups(office)).single;
      expect((await BackupService().validate(saved))['schemaVersion'], 2);
      await evidence.delete();
      final restoredRoot = await BackupService().restoreIsolated(
        backup: saved,
        destination: Directory(p.join(temporary.path, 'restored-office')),
      );
      final restored = open(restoredRoot);
      final repository = AppRepository(restored, storageRoot: restoredRoot);
      expect(
        (await restored.select(restored.clients).get()).single.id,
        'fixture-client',
      );
      expect(
        (await restored.select(restored.legacyTransactionReviews).get())
            .single
            .proposedAmountMinor,
        101,
      );
      final document =
          (await restored.select(restored.caseDocuments).get()).single;
      final restoredFile = File(
        await repository.resolveDocumentPath(document.filePath),
      );
      expect(await restoredFile.readAsString(), 'مستند اختبار اصطناعي فقط');
      expect(
        await restored.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'missing evidence blocks upgrade and preserves v2 with explicit backup',
    () async {
      createV2Fixture(file, documentPath: evidence.path).close();
      await evidence.delete();
      final db = open(office);
      await expectLater(db.select(db.clients).get(), throwsA(anything));
      await close(db);
      final source = native.sqlite3.open(
        file.path,
        mode: native.OpenMode.readOnly,
      );
      try {
        expect(source.userVersion, 2);
        expect(
          source.select('SELECT id FROM case_documents').single['id'],
          'fixture-document',
        );
      } finally {
        source.close();
      }
      final saved = (await backups(office)).single;
      await expectLater(BackupService().validate(saved), throwsFormatException);
      final manifest = await BackupService().validate(
        saved,
        allowIncomplete: true,
      );
      expect(manifest['missingDocumentIds'], ['fixture-document']);
    },
  );

  test('legacy treasury and audit cannot be modified through raw SQL', () async {
    createV2Fixture(file, documentPath: evidence.path).close();
    final db = open(office);
    await db.select(db.clients).get();
    for (final statement in [
      "INSERT INTO transactions (id,title,amount,type) VALUES ('new','x',1,'INCOME')",
      "UPDATE transactions SET amount=99 WHERE id='fixture-transaction'",
      "DELETE FROM transactions WHERE id='fixture-transaction'",
      "UPDATE audit_log SET reason='changed'",
      'DELETE FROM audit_log',
    ]) {
      await expectLater(
        db.customStatement(statement),
        throwsA(anything),
        reason: statement,
      );
    }
    expect((await db.select(db.transactions).get()).single.amount, 1.005);
    expect(
      (await db.select(db.auditLog).get())
          .firstWhere((e) => e.action == 'UPGRADE_V2_V3')
          .actorKind,
      'MIGRATION',
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO cases (id, client_id, case_number) "
        "VALUES ('orphan', 'missing-client', '123')",
      ),
      throwsA(anything),
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test(
    'status and decision changes require reasons and audit before/after',
    () async {
      createV2Fixture(file, documentPath: evidence.path).close();
      final db = open(office);
      final repository = AppRepository(db, storageRoot: office);
      await db.select(db.clients).get();
      await expectLater(
        repository.updateCaseStatus('fixture-case', 'CLOSED', reason: '  '),
        throwsArgumentError,
      );
      await expectLater(
        repository.updateSessionDecision('fixture-session', 'قرار', reason: ''),
        throwsArgumentError,
      );
      expect((await db.select(db.cases).get()).single.revision, 1);
      expect((await db.select(db.sessions).get()).single.revision, 1);
      await repository.updateCaseStatus(
        'fixture-case',
        'CLOSED',
        reason: 'انتهاء الإجراءات',
      );
      await repository.updateSessionDecision(
        'fixture-session',
        'تأجيل للمرافعة',
        reason: 'إثبات القرار الصحيح',
      );
      final currentCase = (await db.select(db.cases).get()).single;
      expect(currentCase.statusCode, 'CLOSED');
      expect(currentCase.status, 'منتهية');
      expect(currentCase.revision, 2);
      expect(currentCase.updatedAt, isNotNull);
      final session = (await db.select(db.sessions).get()).single;
      expect(session.decision, 'تأجيل للمرافعة');
      expect(session.revision, 2);
      final events = await db.select(db.auditLog).get();
      final statusEvent = events.singleWhere(
        (e) => e.action == 'STATUS_CHANGED',
      );
      expect(statusEvent.reason, 'انتهاء الإجراءات');
      expect(
        (jsonDecode(statusEvent.beforeJson!) as Map)['statusCode'],
        'ACTIVE',
      );
      expect(
        (jsonDecode(statusEvent.afterJson!) as Map)['statusCode'],
        'CLOSED',
      );
      final decisionEvent = events.singleWhere(
        (e) => e.action == 'DECISION_CHANGED',
      );
      expect(
        (jsonDecode(decisionEvent.beforeJson!) as Map)['decision'],
        'قرار تجريبي',
      );
      expect(
        (jsonDecode(decisionEvent.afterJson!) as Map)['decision'],
        'تأجيل للمرافعة',
      );
    },
  );

  test(
    'an audit failure rolls status and decision changes back atomically',
    () async {
      createV2Fixture(file, documentPath: evidence.path).close();
      final db = open(office);
      final repository = AppRepository(db, storageRoot: office);
      await db.select(db.clients).get();
      await db.customStatement(
        "CREATE TRIGGER test_deny_audit "
        "BEFORE INSERT ON audit_log BEGIN "
        "SELECT RAISE(ABORT, 'Injected audit write failure'); END",
      );
      await expectLater(
        repository.updateCaseStatus(
          'fixture-case',
          'CLOSED',
          reason: 'سبب اختباري',
        ),
        throwsA(anything),
      );
      await expectLater(
        repository.updateSessionDecision(
          'fixture-session',
          'بديل',
          reason: 'سبب اختباري',
        ),
        throwsA(anything),
      );
      final unchangedCase = (await db.select(db.cases).get()).single;
      final unchangedSession = (await db.select(db.sessions).get()).single;
      expect(unchangedCase.statusCode, 'ACTIVE');
      expect(unchangedCase.revision, 1);
      expect(unchangedCase.updatedAt, isNull);
      expect(unchangedSession.decision, 'قرار تجريبي');
      expect(unchangedSession.revision, 1);
      expect(unchangedSession.updatedAt, isNull);
      expect(await db.select(db.auditLog).get(), hasLength(3));
    },
  );
}
