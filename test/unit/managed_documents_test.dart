import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';

void main() {
  late Directory sandbox;
  late Directory storage;
  late Directory sources;
  late AppDatabase db;
  late AppRepository repository;
  late String caseId;
  const content = 'مستند تجريبي فقط — لا يحتوي على بيانات حقيقية.\nLine 2';

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('seneb-managed-documents-');
    storage = await Directory(p.join(sandbox.path, 'managed')).create();
    sources = await Directory(p.join(sandbox.path, 'sources')).create();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AppRepository(db, storageRoot: storage);
    final clientId = await repository.addClient(name: 'موكل اختباري');
    caseId = await repository.addCase(clientId: clientId, caseNumber: 'TEST-1');
  });

  tearDown(() async {
    await db.close();
    if (await sandbox.exists() &&
        p.isWithin(Directory.systemTemp.absolute.path, sandbox.absolute.path)) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<File> sourceFile([String name = 'synthetic.txt']) =>
      File(p.join(sources.path, name)).writeAsString(content, flush: true);

  Future<void> import(File source, {String title = 'مستند اختباري'}) =>
      repository.addCaseDocument(
        caseId: caseId,
        title: title,
        filePath: source.path,
        fileType: 'txt',
      );

  Future<CaseDocumentEntity> onlyDocument() async =>
      (await repository.getCaseDocuments(caseId)).single;

  Future<void> pendingRow({
    required String id,
    required String source,
    String? checksum,
  }) => db
      .into(db.caseDocuments)
      .insert(
        CaseDocumentsCompanion.insert(
          id: id,
          caseId: caseId,
          title: 'استيراد قيد الاستكمال',
          filePath: 'documents/$id.txt',
          fileType: 'txt',
          sourceFilePath: Value(source),
          storageStatus: const Value('PENDING'),
          checksum: Value(checksum),
        ),
      )
      .then((_) {});

  test(
    'import preserves a readable managed copy after original is deleted',
    () async {
      final source = await sourceFile();
      await import(source);
      final row = await onlyDocument();
      await source.delete();

      final managedPath = await repository.resolveDocumentPath(row.filePath);
      expect(p.isWithin(storage.path, managedPath), isTrue);
      expect(await File(managedPath).readAsString(), content);
      expect(row.storageStatus, 'AVAILABLE');
      expect(p.isAbsolute(row.filePath), isFalse);
      expect(row.filePath, startsWith('documents/'));
      expect(row.sourceFilePath, source.path);
      expect(row.checksum, sha256.convert(utf8.encode(content)).toString());
      expect(row.fileSize, utf8.encode(content).length);
    },
  );

  test(
    'moving the external original cannot invalidate the managed copy',
    () async {
      final source = await sourceFile();
      await import(source);
      await source.rename(p.join(sources.path, 'moved.txt'));
      final row = await onlyDocument();
      expect(
        await File(
          await repository.resolveDocumentPath(row.filePath),
        ).readAsString(),
        content,
      );
    },
  );

  test(
    'retry of an already imported source retains one stable document ID',
    () async {
      final source = await sourceFile();
      await import(source);
      final original = await onlyDocument();
      await import(source);

      final retried = await onlyDocument();
      expect(retried.id, original.id);
      expect(retried.filePath, original.filePath);
      expect(retried.checksum, original.checksum);
      expect((await db.select(db.caseDocuments).get()).length, 1);
    },
  );

  test(
    'retry remains successful after the original source disappears',
    () async {
      final source = await sourceFile();
      await import(source);
      final original = await onlyDocument();
      await source.delete();
      await import(source);

      final retried = await onlyDocument();
      expect(retried.id, original.id);
      expect(retried.storageStatus, 'AVAILABLE');
      expect((await db.select(db.caseDocuments).get()).length, 1);
    },
  );

  test('PENDING import resumes over an interrupted staging file', () async {
    final source = await sourceFile();
    const id = 'pending-before-rename';
    await pendingRow(id: id, source: source.path);
    final destination = File(p.join(storage.path, 'documents', '$id.txt'));
    await destination.parent.create(recursive: true);
    final staged = await File(
      '${destination.path}.part',
    ).writeAsString('partial');

    await repository.initialize();

    final row = await onlyDocument();
    expect(row.id, id);
    expect(row.filePath, 'documents/$id.txt');
    expect(row.storageStatus, 'AVAILABLE');
    expect(await destination.readAsString(), content);
    expect(await staged.exists(), isFalse);
    expect(row.checksum, sha256.convert(utf8.encode(content)).toString());
  });

  test(
    'PENDING metadata resumes after completed rename and source loss',
    () async {
      final source = await sourceFile();
      const id = 'pending-after-rename';
      final checksum = sha256.convert(utf8.encode(content)).toString();
      await pendingRow(id: id, source: source.path, checksum: checksum);
      final destination = File(p.join(storage.path, 'documents', '$id.txt'));
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      await source.delete();

      await repository.initialize();

      final row = await onlyDocument();
      expect(row.id, id);
      expect(row.storageStatus, 'AVAILABLE');
      expect(row.checksum, checksum);
      expect(await destination.readAsString(), content);
    },
  );

  test(
    'unverified PENDING destination is checked against available source',
    () async {
      final source = await sourceFile();
      const id = 'pending-corrupted-destination';
      await pendingRow(id: id, source: source.path);
      final destination = File(p.join(storage.path, 'documents', '$id.txt'));
      await destination.parent.create(recursive: true);
      await destination.writeAsString('damaged existing destination');

      await repository.initialize();

      final row = await onlyDocument();
      expect(await destination.readAsString(), content);
      expect(row.checksum, sha256.convert(utf8.encode(content)).toString());
      expect(row.storageStatus, 'AVAILABLE');
    },
  );

  test(
    'known checksum cannot be replaced by a subsequently changed source',
    () async {
      final source = await sourceFile();
      const id = 'pending-known-checksum';
      final expected = sha256.convert(utf8.encode(content)).toString();
      await pendingRow(id: id, source: source.path, checksum: expected);
      final destination = File(p.join(storage.path, 'documents', '$id.txt'));
      await destination.parent.create(recursive: true);
      await destination.writeAsString('damaged destination');
      await source.writeAsString('changed original after import');

      await repository.initialize();

      final row = await onlyDocument();
      expect(row.storageStatus, isNot('AVAILABLE'));
      expect(row.checksum, expected);
    },
  );

  test('missing input fails without creating an archive record', () async {
    await expectLater(
      import(File(p.join(sources.path, 'missing.txt'))),
      throwsA(isA<FileSystemException>()),
    );
    expect(await repository.getCaseDocuments(caseId), isEmpty);
  });

  test(
    'missing PENDING input is marked missing and remains diagnosable',
    () async {
      await pendingRow(
        id: 'pending-missing',
        source: p.join(sources.path, 'missing.txt'),
      );
      await repository.initialize();
      final row = await onlyDocument();
      expect(row.storageStatus, 'MISSING');
      expect(row.sourceFilePath, p.join(sources.path, 'missing.txt'));
    },
  );

  test('soft deletion retains metadata and the physical file', () async {
    final source = await sourceFile();
    await import(source);
    final row = await onlyDocument();
    final path = await repository.resolveDocumentPath(row.filePath);

    await repository.deleteCaseDocument(row.id);

    expect(await repository.getCaseDocuments(caseId), isEmpty);
    final retained = await db.select(db.caseDocuments).getSingle();
    expect(retained.id, row.id);
    expect(retained.deletedAt, isNotNull);
    expect(await File(path).readAsString(), content);
  });

  test(
    'relative traversal cannot resolve a file outside managed storage',
    () async {
      final outside = await File(
        p.join(sandbox.path, 'outside.txt'),
      ).writeAsString('outside');
      for (final unsafe in [
        '../outside.txt',
        'documents/../../outside.txt',
        r'..\outside.txt',
      ]) {
        await expectLater(
          repository.resolveDocumentPath(unsafe),
          throwsA(isA<FormatException>()),
        );
      }
      expect(await outside.readAsString(), 'outside');
    },
  );

  test(
    'legacy absolute document is adopted before external source removal',
    () async {
      final source = await sourceFile();
      await db
          .into(db.caseDocuments)
          .insert(
            CaseDocumentsCompanion.insert(
              id: 'legacy-document',
              caseId: caseId,
              title: 'مستند قديم اختباري',
              filePath: source.path,
              fileType: 'txt',
            ),
          );

      await repository.initialize();
      await source.delete();

      final row = await onlyDocument();
      expect(row.id, 'legacy-document');
      expect(row.filePath, 'documents/legacy-document.txt');
      expect(row.storageStatus, 'AVAILABLE');
      expect(
        await File(
          await repository.resolveDocumentPath(row.filePath),
        ).readAsString(),
        content,
      );
    },
  );
}
