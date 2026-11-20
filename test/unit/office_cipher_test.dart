import 'dart:io';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/office_cipher.dart';

void main() {
  test(
    'legacy office converts, reopens with recovery phrase, and restores independently',
    () async {
      final root = await Directory.systemTemp.createTemp('office-cipher-test');
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'seneb_law_db.sqlite'));
      final legacy = AppDatabase.openAt(root);
      await legacy.customStatement(
        "INSERT INTO clients(id,name) VALUES('test','marker')",
      );
      await legacy.customStatement(
        "INSERT INTO cases(id,client_id,case_number) VALUES('case','test','123')",
      );
      final attachment = File(p.join(root.path, 'synthetic.txt'));
      await attachment.writeAsString('attachment marker');
      final original = AppRepository(legacy, storageRoot: root);
      await original.addCaseDocument(
        caseId: 'case',
        title: 'fixture',
        filePath: attachment.path,
        fileType: 'txt',
      );
      final relative = (await original.getCaseDocuments(
        'case',
      )).single.filePath;
      await legacy.close();
      final key = OfficeCipher('synthetic recovery phrase 2026');
      final db = AppDatabase.secured(root, key);
      try {
        await AppRepository(db, storageRoot: root).initialize();
        expect(await File(p.join(root.path, relative)).exists(), isFalse);
        expect(await attachment.exists(), isTrue);
        expect((await db.select(db.clients).get()).single.name, 'marker');
      } finally {
        await db.close();
      }
      expect(await OfficeCipher.isPlain(file), isFalse);
      final bare = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        expect(() => bare.select('SELECT * FROM clients'), throwsA(anything));
      } finally {
        bare.close();
      }
      final export = await key.export(
        file,
        root,
        Directory(p.join(root.path, 'exports')),
      );
      final dest = Directory(p.join(root.path, 'restored'));
      await expectLater(
        OfficeCipher('wrong recovery phrase').restore(export, dest),
        throwsA(anything),
      );
      expect(await dest.exists(), isFalse);
      await key.restore(export, dest);
      final restored = AppDatabase.secured(dest, key);
      try {
        final repo = AppRepository(restored, storageRoot: dest);
        await repo.initialize();
        final doc = (await repo.getCaseDocuments('case')).single;
        expect(
          await File(
            await repo.resolveDocumentPath(doc.filePath),
          ).readAsString(),
          'attachment marker',
        );
        expect(
          (await restored.select(restored.clients).get()).single.name,
          'marker',
        );
      } finally {
        await restored.close();
      }
    },
  );
}
