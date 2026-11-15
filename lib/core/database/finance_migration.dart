part of 'database.dart';

Future<void> upgradeToFour(AppDatabase db, Migrator m) async {
  final schema = historical.Schema4(database: db);
  for (final table in <TableInfo<Table, dynamic>>[
    schema.feeAgreements,
    schema.clientLedgerEntries,
    schema.installments,
    schema.paymentAllocations,
    schema.officeExpenses,
    schema.financialReceipts,
    schema.legacyClassifications,
  ]) {
    await m.createTable(table);
  }
  await installFinanceGuards(db);
  await db.customStatement(
    'INSERT INTO audit_log (id, actor_kind, entity_type, entity_id, action, reason, operation_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      const Uuid().v4(),
      'MIGRATION',
      'DATABASE',
      'local',
      'UPGRADE_V3_V4',
      'إنشاء دفاتر مستقلة دون تصنيف تلقائي للمعاملات القديمة',
      const Uuid().v4(),
    ],
  );
}

Future<void> installFinanceGuards(AppDatabase db) async {
  for (final table in [
    'client_ledger_entries',
    'fee_agreements',
    'installments',
    'payment_allocations',
    'office_expenses',
    'financial_receipts',
    'legacy_classifications',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT, 'Financial records cannot be deleted'); END",
    );
  }
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS active_receipt ON financial_receipts(entry_id) WHERE voided_at IS NULL',
  );
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS active_agreement ON fee_agreements(case_id) WHERE voided_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS ledger_client_date ON client_ledger_entries(client_id, occurred_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS allocations_charge ON payment_allocations(charge_id) WHERE voided_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS allocations_payment ON payment_allocations(payment_id) WHERE voided_at IS NULL',
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS legacy_classification_immutable BEFORE UPDATE ON legacy_classifications BEGIN SELECT RAISE(ABORT, 'Classification is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS receipt_snapshot_immutable BEFORE UPDATE ON financial_receipts WHEN NEW.snapshot_json != OLD.snapshot_json OR NEW.number != OLD.number OR NEW.entry_id != OLD.entry_id OR OLD.voided_at IS NOT NULL BEGIN SELECT RAISE(ABORT, 'Receipt snapshot is immutable'); END",
  );
  for (final op in ['INSERT', 'UPDATE']) {
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS ledger_case_${op.toLowerCase()} BEFORE $op ON client_ledger_entries WHEN NEW.case_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM cases WHERE id = NEW.case_id AND client_id = NEW.client_id) BEGIN SELECT RAISE(ABORT, \'Case/client mismatch\'); END',
    );
  }
}
