part of 'database.dart';

Future<void> upgradeToSix(AppDatabase db, Migrator m) async {
  final schema = historical.Schema6(database: db);
  await m.createTable(schema.wordTemplates);
  await m.createTable(schema.wordDocuments);
  await m.createTable(schema.wordShareAttempts);
  await installWordGuards(db);
  await db.customStatement(
    'INSERT INTO audit_log (id,actor_kind,entity_type,entity_id,action,reason,operation_id) VALUES (?,?,?,?,?,?,?)',
    [
      const Uuid().v4(),
      'MIGRATION',
      'DATABASE',
      'local',
      'UPGRADE_V5_V6',
      'إضافة قوالب Word والمستندات المولدة',
      const Uuid().v4(),
    ],
  );
}

Future<void> installWordGuards(AppDatabase db) async {
  for (final table in [
    'word_templates',
    'word_documents',
    'word_share_attempts',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Word history cannot be deleted'); END",
    );
  }
  for (final table in ['word_templates', 'word_documents']) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS ${table}_immutable BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Word snapshot is immutable'); END",
    );
  }
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS word_share_immutable BEFORE UPDATE ON word_share_attempts WHEN NEW.document_id != OLD.document_id OR NEW.actor_id != OLD.actor_id OR NEW.channel != OLD.channel OR NEW.checksum != OLD.checksum OR OLD.status != 'STARTED' BEGIN SELECT RAISE(ABORT,'Share source is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS word_case_client BEFORE INSERT ON word_documents WHEN NEW.case_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM cases WHERE id=NEW.case_id AND client_id=NEW.client_id) BEGIN SELECT RAISE(ABORT,'Word case/client mismatch'); END",
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS word_client_date ON word_documents(client_id,created_at)',
  );
}
