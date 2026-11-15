part of 'database.dart';

Future<void> upgradeToThree(AppDatabase db, Migrator m) async {
  final schema = historical.Schema3(database: db);
  for (final table in <TableInfo<Table, dynamic>>[
    schema.officeLawyers,
    schema.clients,
    schema.cases,
    schema.sessions,
    schema.caseNotes,
    schema.caseDocuments,
  ]) {
    for (final column in table.$columns.where(
      (c) => ['updated_at', 'deleted_at', 'revision'].contains(c.$name),
    )) {
      await m.addColumn(table, column);
    }
  }
  for (final column in [
    schema.officeLawyers.phone,
    schema.officeLawyers.email,
    schema.officeLawyers.barRegistrationNumber,
    schema.officeLawyers.role,
    schema.officeLawyers.isActive,
    schema.officeLawyers.photoDocumentId,
  ]) {
    await m.addColumn(schema.officeLawyers, column);
  }
  // إعادة البناء تسمح بالقيم الافتراضية الزمنية دون تغيير المخطط المستهدف.
  await m.alterTable(
    TableMigration(
      schema.officeLawyers,
      newColumns: [schema.officeLawyers.createdAt],
    ),
  );
  await m.alterTable(
    TableMigration(schema.sessions, newColumns: [schema.sessions.createdAt]),
  );
  for (final column in [
    schema.clients.phoneSecondary,
    schema.clients.whatsappNumber,
    schema.clients.nationalId,
    schema.clients.address,
    schema.clients.email,
    schema.clients.occupation,
    schema.clients.referralSource,
    schema.clients.notes,
    schema.clients.whatsappConsentStatus,
    schema.clients.consentRecordedAt,
    schema.clients.consentRecordedBy,
    schema.clients.consentSource,
  ]) {
    await m.addColumn(schema.clients, column);
  }
  await m.addColumn(schema.cases, schema.cases.statusCode);
  await m.addColumn(schema.caseNotes, schema.caseNotes.visibility);
  for (final column in [
    schema.caseDocuments.sourceFilePath,
    schema.caseDocuments.storageStatus,
    schema.caseDocuments.checksum,
    schema.caseDocuments.fileSize,
  ]) {
    await m.addColumn(schema.caseDocuments, column);
  }
  for (final table in <TableInfo<Table, dynamic>>[
    schema.clientLawyers,
    schema.caseLawyers,
    schema.localCredentials,
    schema.auditLog,
    schema.appSettings,
    schema.legacyTransactionReviews,
  ]) {
    await m.createTable(table);
  }
  await db.customStatement(
    "UPDATE cases SET status_code = CASE status "
    "WHEN 'جارية' THEN 'ACTIVE' WHEN 'منتهية' THEN 'CLOSED' "
    "WHEN 'موقوفة' THEN 'ON_HOLD' WHEN 'مؤرشفة' THEN 'ARCHIVED' ELSE 'LEGACY' END",
  );
  final clients = await db
      .customSelect('SELECT id, assigned_lawyer_id FROM clients')
      .get();
  for (final client in clients) {
    final lawyer = client.readNullable<String>('assigned_lawyer_id');
    if (lawyer != null) {
      await db.customStatement(
        'INSERT INTO client_lawyers '
        '(id, client_id, lawyer_id, change_reason) VALUES (?, ?, ?, ?)',
        [
          const Uuid().v4(),
          client.read<String>('id'),
          lawyer,
          'نقل الإسناد الحالي؛ تاريخ البدء غير معروف',
        ],
      );
    }
  }
  final entries = await db
      .customSelect('SELECT id, amount, case_id, client_id FROM transactions')
      .get();
  for (final entry in entries) {
    final conversion = LegacyMoneyConversion.fromDouble(
      entry.read<double>('amount'),
    );
    final caseId = entry.readNullable<String>('case_id');
    final clientId = entry.readNullable<String>('client_id');
    final linked = caseId == null
        ? null
        : await db
              .customSelect(
                'SELECT client_id FROM cases WHERE id = ?',
                variables: [Variable(caseId)],
              )
              .getSingleOrNull();
    final mismatch =
        linked != null &&
        clientId != null &&
        linked.read<String>('client_id') != clientId;
    await db.customStatement(
      'INSERT INTO legacy_transaction_reviews '
      '(id, legacy_transaction_id, source_amount_text, proposed_amount_minor, '
      'rounding_residual, conversion_error, has_subcent_precision, is_negative, ownership_mismatch) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        entry.read<String>('id'),
        conversion.sourceText,
        conversion.amountMinor,
        conversion.roundingResidual,
        conversion.errorCode,
        conversion.hasSubcentPrecision ? 1 : 0,
        conversion.isNegative ? 1 : 0,
        mismatch ? 1 : 0,
      ],
    );
  }
  await db.customStatement(
    'INSERT INTO audit_log '
    '(id, actor_kind, entity_type, entity_id, action, reason, operation_id) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      const Uuid().v4(),
      'MIGRATION',
      'DATABASE',
      'local',
      'UPGRADE_V2_V3',
      'ترحيل مع حفظ المصادر الأصلية',
      const Uuid().v4(),
    ],
  );
  await db.migrationProbe?.call();
  await installSprintZeroGuards(db);
}

Future<void> installSprintZeroGuards(AppDatabase db) async {
  for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS legacy_${operation.toLowerCase()} '
      'BEFORE $operation ON transactions BEGIN '
      "SELECT RAISE(ABORT, 'Legacy treasury is read-only pending classification'); END",
    );
  }
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS audit_${operation.toLowerCase()} '
      'BEFORE $operation ON audit_log BEGIN '
      "SELECT RAISE(ABORT, 'Audit log is append-only'); END",
    );
  }
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS active_client_lawyer '
    'ON client_lawyers(client_id, lawyer_id) WHERE ended_at IS NULL AND deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS active_case_lawyer '
    'ON case_lawyers(case_id, lawyer_id) WHERE ended_at IS NULL AND deleted_at IS NULL',
  );
  await db.customStatement(
    "CREATE UNIQUE INDEX IF NOT EXISTS active_case_lead "
    "ON case_lawyers(case_id) WHERE assignment_role = 'LEAD' AND ended_at IS NULL AND deleted_at IS NULL",
  );
  await db.customStatement(
    "CREATE UNIQUE INDEX IF NOT EXISTS scoped_setting ON app_settings("
    "COALESCE(scope_owner_id, ''), key) WHERE deleted_at IS NULL",
  );
}
