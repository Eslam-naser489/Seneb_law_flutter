part of 'database.dart';

Future<void> upgradeToFive(AppDatabase db, Migrator m) async {
  final schema = historical.Schema5(database: db);
  for (final table in <TableInfo<Table, dynamic>>[
    schema.reportTemplates,
    schema.caseReports,
    schema.generatedDocuments,
    schema.shareAttempts,
  ]) {
    await m.createTable(table);
  }
  await installReportGuards(db);
  await db.customStatement(
    'INSERT INTO audit_log (id,actor_kind,entity_type,entity_id,action,reason,operation_id) VALUES (?,?,?,?,?,?,?)',
    [
      const Uuid().v4(),
      'MIGRATION',
      'DATABASE',
      'local',
      'UPGRADE_V4_V5',
      'إضافة تقارير ثابتة وسجل محاولات مشاركة مستقل',
      const Uuid().v4(),
    ],
  );
}

Future<void> installReportGuards(AppDatabase db) async {
  for (final table in [
    'case_reports',
    'generated_documents',
    'share_attempts',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Report history cannot be deleted'); END",
    );
  }
  for (final table in ['case_reports', 'generated_documents']) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS ${table}_immutable BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Finalized content is immutable'); END",
    );
  }
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS share_source_immutable BEFORE UPDATE ON share_attempts WHEN NEW.report_id != OLD.report_id OR NEW.actor_id != OLD.actor_id OR NEW.channel != OLD.channel OR NEW.format != OLD.format OR NEW.recipient_snapshot != OLD.recipient_snapshot OR NEW.content_hash != OLD.content_hash OR NEW.artifact_hashes_json != OLD.artifact_hashes_json OR (OLD.status != 'STARTED' AND NEW.status != OLD.status) OR (OLD.user_confirmed_sent_at IS NOT NULL AND NEW.user_confirmed_sent_at IS NOT OLD.user_confirmed_sent_at) BEGIN SELECT RAISE(ABORT,'Share source is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS report_case_client BEFORE INSERT ON case_reports WHEN NEW.case_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM cases WHERE id=NEW.case_id AND client_id=NEW.client_id) BEGIN SELECT RAISE(ABORT,'Report case/client mismatch'); END",
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS reports_client_date ON case_reports(client_id,created_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS shares_report_date ON share_attempts(report_id,created_at)',
  );
  for (final row in [
    [
      'postponement',
      'تأجيل الجلسة',
      'تأجلت الجلسة إلى {{value}}.',
      'التاريخ والسبب إن وجد',
    ],
    [
      'judgment',
      'صدور حكم',
      'صدر حكم في القضية: {{value}}.',
      'منطوق الحكم المراجع',
    ],
    [
      'memorandum',
      'إيداع مذكرة',
      'تم إيداع مذكرة: {{value}}.',
      'تاريخ الإيداع وبيان المذكرة',
    ],
  ]) {
    await db.customStatement(
      'INSERT OR IGNORE INTO report_templates(id,name,body,field_label) VALUES (?,?,?,?)',
      row,
    );
  }
}
