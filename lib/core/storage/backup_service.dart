import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

class BackupResult {
  final Directory directory;
  final List<String> missingDocumentIds;
  const BackupResult(this.directory, this.missingDocumentIds);
  bool get isComplete => missingDocumentIds.isEmpty;
}

/// نسخة مستقلة تشمل قاعدة متسقة والملفات المقروءة.
class BackupService {
  static const formatVersion = 1;

  Future<BackupResult> create({
    required File databaseFile,
    required Directory storageRoot,
    required Directory destinationRoot,
  }) async {
    await destinationRoot.create(recursive: true);
    final id = const Uuid().v4();
    final staging = Directory(p.join(destinationRoot.path, '.partial-$id'));
    final completed = Directory(
      p.join(destinationRoot.path, 'seneb-backup-$id'),
    );
    await staging.create();
    try {
      final snapshot = File(p.join(staging.path, 'database.sqlite'));
      final source = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
      try {
        final target = sqlite3.open(snapshot.path);
        try {
          await source.backup(target).drain<void>();
        } finally {
          target.close();
        }
      } finally {
        source.close();
      }
      final db = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
      final files = <Map<String, Object?>>[];
      final missing = <String>[];
      late int version;
      late Map<String, int> counts;
      try {
        _checkDatabase(db);
        version = db.userVersion;
        counts = _rowCounts(db);
        if (counts.containsKey('case_documents')) {
          for (final row in db.select('SELECT * FROM case_documents')) {
            final documentId = row['id'] as String;
            final oldPath = row['file_path'] as String;
            File? original;
            try {
              original = File(
                p.isAbsolute(oldPath)
                    ? oldPath
                    : safePath(storageRoot, oldPath),
              );
              if (!await original.exists()) original = null;
            } on FormatException {
              original = null;
            }
            if (original == null) {
              missing.add(documentId);
              continue;
            }
            final relative = 'files/${const Uuid().v4()}';
            final copy = File(safePath(staging, relative));
            await copy.parent.create(recursive: true);
            await original.copy(copy.path);
            final copiedHash = await hashFile(copy);
            final copiedSize = await copy.length();
            if ((row.keys.contains('checksum') &&
                    row['checksum'] != null &&
                    row['checksum'] != copiedHash) ||
                (row.keys.contains('file_size') &&
                    row['file_size'] != null &&
                    row['file_size'] != copiedSize)) {
              throw const FormatException(
                'Managed document integrity check failed',
              );
            }
            files.add({
              'documentId': documentId,
              'sourcePath': oldPath,
              'extension':
                  RegExp(
                    r'^\.[a-zA-Z0-9]{1,10}$',
                  ).hasMatch(p.extension(oldPath))
                  ? p.extension(oldPath)
                  : '',
              'path': relative,
              'size': copiedSize,
              'sha256': copiedHash,
            });
          }
        }
      } finally {
        db.close();
      }
      final manifest = {
        'formatVersion': formatVersion,
        'schemaVersion': version,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'databaseSha256': await hashFile(snapshot),
        'databaseSize': await snapshot.length(),
        'rowCounts': counts,
        'files': files,
        'missingDocumentIds': missing,
        'encrypted': false,
      };
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      await validate(staging, allowIncomplete: true);
      await staging.rename(completed.path);
      return BackupResult(completed, List.unmodifiable(missing));
    } catch (_) {
      if (await staging.exists() &&
          p.isWithin(destinationRoot.absolute.path, staging.absolute.path)) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> validate(
    Directory backup, {
    bool allowIncomplete = false,
  }) async {
    final manifestFile = File(safePath(backup, 'manifest.json'));
    if (await manifestFile.length() > 16 * 1024 * 1024) {
      throw const FormatException('Backup manifest too large');
    }
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    if (manifest['formatVersion'] != formatVersion ||
        manifest['schemaVersion'] is! int ||
        (manifest['schemaVersion'] as int) < 1 ||
        (manifest['schemaVersion'] as int) > 6) {
      throw const FormatException('Unsupported backup version');
    }
    final missing = manifest['missingDocumentIds'] as List;
    if (!allowIncomplete && missing.isNotEmpty) {
      throw const FormatException('Backup has missing documents');
    }
    final database = File(safePath(backup, 'database.sqlite'));
    await _verify(
      database,
      manifest['databaseSize'],
      manifest['databaseSha256'],
    );
    final db = sqlite3.open(database.path, mode: OpenMode.readOnly);
    try {
      _checkDatabase(db);
      if (db.userVersion != manifest['schemaVersion'] ||
          !_sameCounts(_rowCounts(db), manifest['rowCounts'] as Map)) {
        throw const FormatException('Backup database metadata mismatch');
      }
      final knownIds = _rowCounts(db).containsKey('case_documents')
          ? db
                .select('SELECT id FROM case_documents')
                .map((r) => r['id'])
                .toSet()
          : <Object?>{};
      final listedIds = <Object?>{};
      final recorded = <Object?, Map<String, Object?>>{
        if (knownIds.isNotEmpty)
          for (final row in db.select('SELECT * FROM case_documents'))
            row['id']: Map<String, Object?>.from(row),
      };
      for (final raw in manifest['files'] as List) {
        final item = raw as Map;
        if (!knownIds.contains(item['documentId']) ||
            !listedIds.add(item['documentId'])) {
          throw const FormatException('Invalid backup document mapping');
        }
        final document = recorded[item['documentId']]!;
        if ((document['checksum'] != null &&
                document['checksum'] != item['sha256']) ||
            (document['file_size'] != null &&
                document['file_size'] != item['size'])) {
          throw const FormatException('Document metadata checksum mismatch');
        }
        await _verify(
          File(safePath(backup, item['path'] as String)),
          item['size'],
          item['sha256'],
        );
      }
      for (final id in missing) {
        if (!knownIds.contains(id) || !listedIds.add(id)) {
          throw const FormatException('Invalid missing document mapping');
        }
      }
      if (listedIds.length != knownIds.length) {
        throw const FormatException('Incomplete backup manifest');
      }
    } finally {
      db.close();
    }
    return manifest;
  }

  /// الاستعادة هنا إلى مجلد جديد فقط؛ لا تستبدل قاعدة مفتوحة.
  Future<Directory> restoreIsolated({
    required Directory backup,
    required Directory destination,
    bool allowIncomplete = false,
  }) async {
    if (await destination.exists()) {
      throw const FileSystemException('Restore destination must not exist');
    }
    final manifest = await validate(backup, allowIncomplete: allowIncomplete);
    final staging = Directory(
      '${destination.path}.partial-${const Uuid().v4()}',
    );
    await staging.create(recursive: true);
    try {
      final target = await File(
        p.join(backup.path, 'database.sqlite'),
      ).copy(p.join(staging.path, 'seneb_law_db.sqlite'));
      await _verify(
        target,
        manifest['databaseSize'],
        manifest['databaseSha256'],
      );
      final db = sqlite3.open(target.path);
      try {
        db.execute('BEGIN IMMEDIATE');
        final columns = db
            .select('PRAGMA table_info(case_documents)')
            .map((r) => r['name'])
            .toSet();
        for (final raw in manifest['files'] as List) {
          final item = raw as Map;
          final extension = (item['extension'] as String?) ?? '';
          if (extension.isNotEmpty &&
              !RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)) {
            throw const FormatException('Invalid document extension');
          }
          final relative = 'documents/${const Uuid().v4()}$extension';
          final file = File(safePath(staging, relative));
          await file.parent.create(recursive: true);
          await File(safePath(backup, item['path'] as String)).copy(file.path);
          await _verify(file, item['size'], item['sha256']);
          db.execute('UPDATE case_documents SET file_path = ? WHERE id = ?', [
            relative,
            item['documentId'],
          ]);
          if (columns.contains('storage_status')) {
            db.execute(
              'UPDATE case_documents SET storage_status = ?, '
              'checksum = ?, file_size = ? WHERE id = ?',
              ['AVAILABLE', item['sha256'], item['size'], item['documentId']],
            );
          }
        }
        for (final id in manifest['missingDocumentIds'] as List) {
          db.execute('UPDATE case_documents SET file_path = ? WHERE id = ?', [
            'missing/${const Uuid().v4()}',
            id,
          ]);
          if (columns.contains('storage_status')) {
            db.execute(
              'UPDATE case_documents SET storage_status = ? WHERE id = ?',
              ['MISSING', id],
            );
          }
        }
        db.execute('COMMIT');
        _checkDatabase(db);
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      } finally {
        db.close();
      }
      await staging.rename(destination.path);
      return destination;
    } catch (_) {
      if (await staging.exists() &&
          p.equals(
            staging.parent.absolute.path,
            destination.parent.absolute.path,
          )) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  static String safePath(Directory root, String relative) {
    if (FileSystemEntity.typeSync(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Symbolic storage roots are not allowed');
    }
    if (relative.isEmpty ||
        p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative.split('/').contains('..')) {
      throw const FormatException('Unsafe relative path');
    }
    final target = p.normalize(p.join(root.absolute.path, relative));
    if (!p.isWithin(root.absolute.path, target)) {
      throw const FormatException('Path outside storage root');
    }
    // لا نتبع روابط رمزية داخل النسخة.
    var current = root.absolute.path;
    for (final part in p.split(p.relative(target, from: root.absolute.path))) {
      current = p.join(current, part);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Symbolic links are not allowed');
      }
    }
    return target;
  }

  static Future<String> hashFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<void> _verify(File file, Object? size, Object? hash) async {
    if (!await file.exists() ||
        await file.length() != size ||
        await hashFile(file) != hash) {
      throw const FormatException('Backup checksum mismatch');
    }
  }

  static void _checkDatabase(Database db) {
    final integrity = db.select('PRAGMA integrity_check');
    if (integrity.length != 1 ||
        integrity.first.values.first != 'ok' ||
        db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('Database integrity check failed');
    }
  }

  static Map<String, int> _rowCounts(Database db) => {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE "
      "type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String:
          db
                  .select(
                    'SELECT COUNT(*) AS n FROM '
                    '"${(row['name'] as String).replaceAll('"', '""')}"',
                  )
                  .first['n']
              as int,
  };

  static bool _sameCounts(Map<String, int> actual, Map expected) =>
      actual.length == expected.length &&
      actual.entries.every((e) => expected[e.key] == e.value);
}
