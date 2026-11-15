import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/backup_service.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/v2_fixture.dart';

void main() {
  late Directory temporary;
  late Directory office;
  late File database;
  late File sourceDocument;
  late BackupService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('seneb-backup-test-');
    office = await Directory(p.join(temporary.path, 'office')).create();
    database = File(p.join(office.path, 'seneb_law_db.sqlite'));
    sourceDocument = await File(
      p.join(temporary.path, 'synthetic-source.txt'),
    ).writeAsString('محتوى مستند اختباري فقط\n');
    service = BackupService();
  });

  tearDown(() async {
    // Every test owns this exact temporary directory, never the user's storage.
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<BackupResult> backup({bool wal = false}) async {
    final db = createV2Fixture(
      database,
      documentPath: sourceDocument.path,
      wal: wal,
    );
    db.close();
    return service.create(
      databaseFile: database,
      storageRoot: office,
      destinationRoot: Directory(p.join(temporary.path, 'backups')),
    );
  }

  Future<void> editManifest(
    Directory directory,
    void Function(Map<String, dynamic>) edit,
  ) async {
    final file = File(p.join(directory.path, 'manifest.json'));
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    edit(manifest);
    await file.writeAsString(jsonEncode(manifest));
  }

  Future<File> migratedManagedDocument() async {
    final legacy = createV2Fixture(database, documentPath: sourceDocument.path);
    legacy.close();
    final db = AppDatabase.openAt(office);
    try {
      final repository = AppRepository(db, storageRoot: office);
      await repository.initialize();
      final document = (await repository.getCaseDocuments(
        'fixture-case',
      )).single;
      expect(document.storageStatus, 'AVAILABLE');
      expect(document.checksum, await BackupService.hashFile(sourceDocument));
      expect(document.fileSize, await sourceDocument.length());
      expect(p.isAbsolute(document.filePath), isFalse);
      return File(BackupService.safePath(office, document.filePath));
    } finally {
      await db.close();
    }
  }

  for (final changeLength in [false, true]) {
    test(
      'v3 backup refuses managed file ${changeLength ? 'size change' : 'same-size corruption'} against recorded metadata',
      () async {
        final managed = await migratedManagedDocument();
        final bytes = await managed.readAsBytes();
        final originalHash = await BackupService.hashFile(managed);
        if (changeLength) {
          await managed.writeAsBytes([...bytes, 0x21], flush: true);
        } else {
          bytes[0] ^= 0x01;
          await managed.writeAsBytes(bytes, flush: true);
        }
        final destination = Directory(
          p.join(temporary.path, 'damaged-backups'),
        );
        await expectLater(
          service.create(
            databaseFile: database,
            storageRoot: office,
            destinationRoot: destination,
          ),
          throwsFormatException,
        );
        expect(await destination.list().toList(), isEmpty);
        final unchanged = sqlite3.open(database.path, mode: OpenMode.readOnly);
        try {
          final row = unchanged
              .select('SELECT checksum, file_size FROM case_documents')
              .single;
          expect(row['checksum'], originalHash);
          expect(row['file_size'], await sourceDocument.length());
        } finally {
          unchanged.close();
        }
      },
    );
  }

  test(
    'v3 validation rejects changed file even when manifest hash and size are updated',
    () async {
      await migratedManagedDocument();
      final result = await service.create(
        databaseFile: database,
        storageRoot: office,
        destinationRoot: Directory(p.join(temporary.path, 'managed-backups')),
      );
      final manifest = await service.validate(result.directory);
      final mapping = (manifest['files'] as List).single as Map;
      final archived = File(
        BackupService.safePath(result.directory, mapping['path'] as String),
      );
      final originalDatabaseHash = manifest['databaseSha256'];
      await archived.writeAsBytes([
        ...(await archived.readAsBytes()),
        0x21,
      ], flush: true);
      final newHash = await BackupService.hashFile(archived);
      final newSize = await archived.length();
      await editManifest(result.directory, (changed) {
        final file = (changed['files'] as List).single as Map;
        file['sha256'] = newHash;
        file['size'] = newSize;
        expect(changed['databaseSha256'], originalDatabaseHash);
      });
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
      final destination = Directory(p.join(temporary.path, 'tampered-restore'));
      await expectLater(
        service.restoreIsolated(
          backup: result.directory,
          destination: destination,
        ),
        throwsFormatException,
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test(
    'v2 backup preserves all tables, exact source amount and independent files',
    () async {
      final result = await backup();
      expect(result.isComplete, isTrue);
      final manifest = await service.validate(result.directory);
      expect(manifest['schemaVersion'], 2);
      expect((manifest['rowCounts'] as Map).length, 7);
      expect((manifest['rowCounts'] as Map).values, everyElement(1));
      final snapshot = sqlite3.open(
        p.join(result.directory.path, 'database.sqlite'),
      );
      try {
        expect(snapshot.userVersion, 2);
        expect(
          snapshot.select('SELECT amount FROM transactions').single['amount'],
          1.005,
        );
        expect(
          snapshot
              .select('SELECT circle_number, decision FROM sessions')
              .single,
          containsPair('circle_number', '١٢'),
        );
        expect(snapshot.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        snapshot.close();
      }
      final files = manifest['files'] as List;
      expect(files, hasLength(1));
      final archived = File(
        p.join(result.directory.path, (files.single as Map)['path'] as String),
      );
      expect(await archived.readAsBytes(), await sourceDocument.readAsBytes());
      expect(await archived.length(), (files.single as Map)['size']);
      expect(
        await BackupService.hashFile(archived),
        (files.single as Map)['sha256'],
      );
    },
  );

  test(
    'online backup includes committed WAL data but excludes an uncommitted write',
    () async {
      final writer = createV2Fixture(
        database,
        documentPath: sourceDocument.path,
        wal: true,
      );
      try {
        expect(
          writer.select('PRAGMA journal_mode').single.values.single,
          'wal',
        );
        writer.execute(
          'INSERT INTO case_notes (id, case_id, content, created_at) '
          'VALUES (?, ?, ?, ?)',
          [
            'committed-note',
            'fixture-case',
            'committed WAL record',
            1700000005,
          ],
        );
        writer.execute('BEGIN IMMEDIATE');
        writer.execute(
          'INSERT INTO case_notes (id, case_id, content, created_at) '
          'VALUES (?, ?, ?, ?)',
          [
            'pending-note',
            'fixture-case',
            'must not enter snapshot',
            1700000006,
          ],
        );
        final result = await service.create(
          databaseFile: database,
          storageRoot: office,
          destinationRoot: Directory(p.join(temporary.path, 'wal-backups')),
        );
        writer.execute('ROLLBACK');
        final snapshot = sqlite3.open(
          p.join(result.directory.path, 'database.sqlite'),
        );
        try {
          final ids = snapshot
              .select('SELECT id FROM case_notes')
              .map((r) => r['id']);
          expect(ids, containsAll(['fixture-note', 'committed-note']));
          expect(ids, isNot(contains('pending-note')));
        } finally {
          snapshot.close();
        }
      } finally {
        if (!writer.autocommit) writer.execute('ROLLBACK');
        writer.close();
      }
    },
  );

  test(
    'isolated restore remains readable after original document is removed',
    () async {
      final result = await backup();
      final originalBytes = await sourceDocument.readAsBytes();
      await sourceDocument.delete();
      final destination = Directory(p.join(temporary.path, 'restored-office'));
      final restored = await service.restoreIsolated(
        backup: result.directory,
        destination: destination,
      );
      final db = sqlite3.open(p.join(restored.path, 'seneb_law_db.sqlite'));
      try {
        final row = db
            .select('SELECT id, file_path FROM case_documents')
            .single;
        expect(row['id'], 'fixture-document');
        final relative = row['file_path'] as String;
        expect(p.isAbsolute(relative), isFalse);
        final restoredFile = File(BackupService.safePath(restored, relative));
        expect(await restoredFile.readAsBytes(), originalBytes);
        expect(
          db.select('SELECT id FROM transactions').single['id'],
          'fixture-transaction',
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
      expect(await service.validate(result.directory), isNotEmpty);
    },
  );

  test(
    'missing source documents are explicit and refused unless opted in',
    () async {
      final db = createV2Fixture(database, documentPath: sourceDocument.path);
      db.close();
      await sourceDocument.delete();
      final result = await service.create(
        databaseFile: database,
        storageRoot: office,
        destinationRoot: Directory(p.join(temporary.path, 'missing-backups')),
      );
      expect(result.isComplete, isFalse);
      expect(result.missingDocumentIds, ['fixture-document']);
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
      final blocked = Directory(p.join(temporary.path, 'blocked-restore'));
      await expectLater(
        service.restoreIsolated(backup: result.directory, destination: blocked),
        throwsFormatException,
      );
      expect(await blocked.exists(), isFalse);
      final allowed = await service.restoreIsolated(
        backup: result.directory,
        destination: Directory(p.join(temporary.path, 'allowed-restore')),
        allowIncomplete: true,
      );
      final restoredDb = sqlite3.open(
        p.join(allowed.path, 'seneb_law_db.sqlite'),
      );
      try {
        final path =
            restoredDb
                    .select('SELECT file_path FROM case_documents')
                    .single['file_path']
                as String;
        expect(path, startsWith('missing/'));
        expect(
          await File(BackupService.safePath(allowed, path)).exists(),
          isFalse,
        );
      } finally {
        restoredDb.close();
      }
    },
  );

  test(
    'database corruption rejects restore before creating destination',
    () async {
      final result = await backup();
      final snapshot = File(p.join(result.directory.path, 'database.sqlite'));
      final bytes = await snapshot.readAsBytes();
      bytes[0] = bytes[0] ^ 0xff;
      await snapshot.writeAsBytes(bytes, flush: true);
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
      final destination = Directory(
        p.join(temporary.path, 'corrupt-db-restore'),
      );
      await expectLater(
        service.restoreIsolated(
          backup: result.directory,
          destination: destination,
        ),
        throwsFormatException,
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test(
    'attachment corruption is detected even when its length is unchanged',
    () async {
      final result = await backup();
      final manifest = await service.validate(result.directory);
      final relative =
          ((manifest['files'] as List).single as Map)['path'] as String;
      final attachment = File(
        BackupService.safePath(result.directory, relative),
      );
      final bytes = await attachment.readAsBytes();
      bytes[0] = bytes[0] ^ 0x01;
      await attachment.writeAsBytes(bytes, flush: true);
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
    },
  );

  test(
    'manifest traversal and duplicate document mappings are rejected',
    () async {
      final result = await backup();
      final original = await File(
        p.join(result.directory.path, 'manifest.json'),
      ).readAsString();
      await editManifest(result.directory, (manifest) {
        ((manifest['files'] as List).single as Map)['path'] =
            '../synthetic-source.txt';
      });
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
      await File(
        p.join(result.directory.path, 'manifest.json'),
      ).writeAsString(original);
      await editManifest(result.directory, (manifest) {
        final files = manifest['files'] as List;
        files.add(Map<String, dynamic>.from(files.single as Map));
      });
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
    },
  );

  test(
    'metadata tampering and omitted document mapping are rejected',
    () async {
      final result = await backup();
      final original = await File(
        p.join(result.directory.path, 'manifest.json'),
      ).readAsString();
      await editManifest(result.directory, (manifest) {
        (manifest['rowCounts'] as Map)['transactions'] = 0;
      });
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
      await File(
        p.join(result.directory.path, 'manifest.json'),
      ).writeAsString(original);
      await editManifest(result.directory, (manifest) {
        manifest['files'] = [];
      });
      await expectLater(
        service.validate(result.directory),
        throwsFormatException,
      );
    },
  );

  test('occupied restore destination remains untouched', () async {
    final result = await backup();
    final destination = await Directory(
      p.join(temporary.path, 'occupied'),
    ).create();
    final sentinel = await File(
      p.join(destination.path, 'keep.txt'),
    ).writeAsString('keep');
    await expectLater(
      service.restoreIsolated(
        backup: result.directory,
        destination: destination,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sentinel.readAsString(), 'keep');
    expect(await destination.list().length, 1);
  });

  test('unsafe relative paths cannot escape a storage root', () {
    for (final path in [
      '',
      '..',
      '../escape',
      'files/../../escape',
      r'files\escape',
      p.join(temporary.absolute.path, 'absolute'),
    ]) {
      expect(
        () => BackupService.safePath(office, path),
        throwsFormatException,
        reason: path,
      );
    }
  });

  test(
    'failed creation removes partial backup and leaves source intact',
    () async {
      final db = createV2Fixture(database, documentPath: sourceDocument.path);
      db.close();
      final bytes = await database.readAsBytes();
      final invalidSource = await File(
        p.join(office.path, 'invalid-source.bin'),
      ).writeAsString('not SQLite');
      final destination = Directory(p.join(temporary.path, 'failed-backups'));
      await expectLater(
        service.create(
          databaseFile: invalidSource,
          storageRoot: office,
          destinationRoot: destination,
        ),
        throwsA(anything),
      );
      expect(await destination.list().toList(), isEmpty);
      expect(await database.readAsBytes(), bytes);
    },
  );
}
