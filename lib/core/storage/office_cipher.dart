import 'dart:convert';
import 'dart:io';
import 'backup_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// SQLite3MC derives its page key from the recovery phrase and a per-file salt.
class OfficeCipher {
  OfficeCipher(String phrase) : _encoded = base64Encode(utf8.encode(phrase)) {
    if (phrase.trim().length < 12) {
      throw const FormatException('أدخل عبارة استعادة من 12 حرفًا على الأقل.');
    }
  }
  final String _encoded;
  void configure(Database db, {bool convert = false}) {
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA ${convert ? 'rekey' : 'key'}='$_encoded'");
    db.select(
      'SELECT sqlite3mc_version()',
    ); // Fail closed with a stock SQLite binary.
    db.select('SELECT count(*) FROM sqlite_master');
  }

  Database open(File file, {bool readOnly = false}) {
    final db = sqlite3.open(
      file.path,
      mode: readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate,
    );
    try {
      configure(db);
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static Future<bool> isPlain(File file) async {
    if (!await file.exists() || await file.length() < 16) return false;
    final f = await file.open();
    try {
      return latin1.decode(await f.read(16)) == 'SQLite format 3\x00';
    } finally {
      await f.close();
    }
  }

  static const payloadSchema =
      'CREATE TABLE IF NOT EXISTS seneb_backup_files(id TEXT PRIMARY KEY, extension TEXT NOT NULL, digest TEXT NOT NULL, bytes BLOB NOT NULL)';

  // sqlite3_backup rejects cross-key copies. ATTACH reads a consistent snapshot
  // while every page written to main uses the destination key.
  void _copy(Database target, File database, bool plain) {
    target.execute('ATTACH DATABASE ? AS original KEY ?', [
      database.path,
      plain ? '' : _encoded,
    ]);
    target.execute('BEGIN');
    final schema = target.select(
      "SELECT type,name,sql FROM original.sqlite_master WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type != 'table',rowid",
    );
    for (final row in schema) {
      target.execute(row['sql'] as String);
      if (row['type'] == 'table') {
        final name = (row['name'] as String).replaceAll('"', '""');
        target.execute(
          'INSERT INTO main."$name" SELECT * FROM original."$name"',
        );
      }
    }
    if (target
        .select(
          "SELECT name FROM original.sqlite_master WHERE name='sqlite_sequence'",
        )
        .isNotEmpty) {
      target.execute('DELETE FROM main.sqlite_sequence');
      target.execute(
        'INSERT INTO main.sqlite_sequence SELECT * FROM original.sqlite_sequence',
      );
    }
    target.userVersion =
        target.select('PRAGMA original.user_version').single.values.single
            as int;
    target.execute('COMMIT');
    target.execute('DETACH DATABASE original');
  }

  Future<File> export(
    File database,
    Directory root,
    Directory destination, {
    bool plain = false,
  }) async {
    await destination.create(recursive: true);
    final out = File(
      p.join(destination.path, 'seneb-${const Uuid().v4()}.seneb'),
    );
    final stage = File('${out.path}.partial');

    try {
      final target = open(stage);
      try {
        _copy(target, database, plain);
        target.execute(payloadSchema);
        target.execute('BEGIN');
        if (target
            .select(
              "SELECT name FROM sqlite_master WHERE name='case_documents'",
            )
            .isNotEmpty) {
          for (final row in target.select(
            'SELECT * FROM case_documents WHERE id NOT IN (SELECT id FROM seneb_backup_files)',
          )) {
            final path = row['file_path'] as String;
            var file = File(
              p.isAbsolute(path) ? path : BackupService.safePath(root, path),
            );
            if (!await file.exists() &&
                row.keys.contains('source_file_path') &&
                row['source_file_path'] != null) {
              final origin = row['source_file_path'] as String;
              file = File(
                p.isAbsolute(origin)
                    ? origin
                    : BackupService.safePath(root, origin),
              );
            }
            final bytes = await file.readAsBytes();
            final digest = sha256.convert(bytes).toString();
            if (row.keys.contains('checksum') &&
                row['checksum'] != null &&
                row['checksum'] != digest) {
              throw const FormatException('تغير أحد المرفقات.');
            }
            final ext = p.extension(path).toLowerCase();
            target.execute('INSERT INTO seneb_backup_files VALUES(?,?,?,?)', [
              row['id'],
              RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(ext) ? ext : '',
              digest,
              bytes,
            ]);
          }
        }
        target.execute('COMMIT');
      } finally {
        target.close();
      }
      final verified = open(stage, readOnly: true);
      try {
        _check(verified);
      } finally {
        verified.close();
      }
      if (await isPlain(stage)) throw StateError('تعذر تشفير النسخة.');
      return await stage.rename(out.path);
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }

  static void _check(Database db) {
    if (db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
        db.select('PRAGMA foreign_key_check').isNotEmpty ||
        db.userVersion < 2 ||
        db.userVersion > 6) {
      throw const FormatException('نسخة غير سليمة أو إصدار غير مدعوم.');
    }
    final ids = db
        .select('SELECT id FROM case_documents')
        .map((r) => r['id'])
        .toSet();
    for (final row in db.select('SELECT id FROM seneb_backup_files')) {
      if (!ids.remove(row['id'])) {
        throw const FormatException('مرفق غير معروف.');
      }
      final f = db.select(
        'SELECT bytes,digest FROM seneb_backup_files WHERE id=?',
        [row['id']],
      ).single;
      if (sha256.convert(f['bytes'] as List<int>).toString() != f['digest']) {
        throw const FormatException('مرفق تالف.');
      }
    }
    if (ids.isNotEmpty) throw const FormatException('مرفقات ناقصة.');
  }

  Future<Directory> restore(File archive, Directory destination) async {
    if (await destination.exists()) throw StateError('اختر مجلدًا جديدًا.');
    final stage = Directory('${destination.path}.partial-${const Uuid().v4()}');
    await stage.create(recursive: true);
    try {
      final file = await archive.copy(
        p.join(stage.path, 'seneb_law_db.sqlite'),
      );
      final db = open(file);
      try {
        _check(db);
        for (final row in db.select(
          'SELECT id,extension FROM seneb_backup_files',
        )) {
          final ext = row['extension'] as String;
          if (ext.isNotEmpty && !RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(ext)) {
            throw const FormatException('امتداد غير صالح.');
          }
          db.execute('UPDATE case_documents SET file_path=? WHERE id=?', [
            'documents/${const Uuid().v4()}$ext',
            row['id'],
          ]);
        }
      } finally {
        db.close();
      }
      return await stage.rename(destination.path);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }
}
