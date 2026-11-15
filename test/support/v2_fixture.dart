import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Only synthetic records. Schema SQL comes from the captured pre-change v2
/// export, so migration/recovery tests do not silently create today's schema.
Database createV2Fixture(
  File file, {
  String? documentPath,
  bool wal = false,
  bool populate = true,
}) {
  file.parent.createSync(recursive: true);
  final schema =
      jsonDecode(
            File(
              'test/drift/schemas/app/drift_schema_v2.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final db = sqlite3.open(file.path);
  try {
    db.execute('PRAGMA foreign_keys = ON');
    if (wal) db.execute('PRAGMA journal_mode = WAL');
    for (final raw in schema['fixed_sql'] as List) {
      final entity = raw as Map;
      for (final statement in entity['sql'] as List) {
        if ((statement as Map)['dialect'] == 'sqlite') {
          db.execute(statement['sql'] as String);
        }
      }
    }
    db.userVersion = 2;
    if (populate) {
      db.execute('BEGIN');
      db.execute('INSERT INTO office_lawyers (id, name) VALUES (?, ?)', [
        'fixture-lawyer',
        'محامٍ تجريبي',
      ]);
      db.execute(
        'INSERT INTO clients (id, name, phone, assigned_lawyer_id, '
        'is_archived, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'fixture-client',
          'موكل اختباري',
          '01000000000',
          'fixture-lawyer',
          0,
          1700000000,
        ],
      );
      db.execute(
        'INSERT INTO cases (id, client_id, case_number, opponent_name, status, '
        'created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'fixture-case',
          'fixture-client',
          '١٢٣/٢٠٢٦',
          'خصم اختباري',
          'جارية',
          1700000001,
        ],
      );
      db.execute(
        'INSERT INTO sessions (id, case_id, session_date, court_location, '
        'circle_number, decision) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'fixture-session',
          'fixture-case',
          1700000100,
          'محكمة اختبار',
          '١٢',
          'قرار تجريبي',
        ],
      );
      db.execute(
        'INSERT INTO case_notes (id, case_id, content, created_at) '
        'VALUES (?, ?, ?, ?)',
        ['fixture-note', 'fixture-case', 'ملاحظة اختبارية داخلية', 1700000002],
      );
      db.execute(
        'INSERT INTO transactions (id, title, amount, type, transaction_date, '
        'case_id, client_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'fixture-transaction',
          'دفعة اختبارية',
          1.005,
          'INCOME',
          1700000003,
          'fixture-case',
          'fixture-client',
        ],
      );
      db.execute(
        'INSERT INTO case_documents (id, case_id, title, file_path, file_type, '
        'uploaded_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'fixture-document',
          'fixture-case',
          'مستند اصطناعي',
          documentPath ?? 'documents/synthetic-evidence.txt',
          'txt',
          1700000004,
        ],
      );
      db.execute('COMMIT');
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}
