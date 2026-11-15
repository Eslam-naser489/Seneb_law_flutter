import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/database.dart';
import 'generated/schema.dart';

// Populated fixtures and recovery are tested in sprint_zero_migration_test.dart.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  for (final version in [2, 3, 4]) {
    test('v$version upgrade matches the captured v5 schema', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(version);
      final db = AppDatabase.forTesting(schema.newConnection());
      try {
        await verifier.migrateAndValidate(db, 5);
      } finally {
        await db.close();
      }
    });
  }
}
