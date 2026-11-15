part of 'app_repository.dart';

/// واجهة العمل تُربط بجلسة واحدة، حتى بعد تبديل المستخدم.
class ScopedAppRepository extends AppRepository {
  ScopedAppRepository._(this._access, this.session)
    : super(_access._db, storageRoot: _access._base.storageRoot);

  final OfficeAccess _access;
  final StaffSession session;
  OfficeLawyerEntity get staff => session.person;
  bool get isOwner => session.role == OfficeRole.owner;
  bool get canEdit =>
      isOwner ||
      session.role == OfficeRole.partner ||
      session.role == OfficeRole.lawyer;
  bool get canReadFinance => canEdit;

  Future<T> _read<T>(Future<T> Function() operation) async {
    await _access._validate(session);
    final result = await operation();
    await _access._validate(session);
    return result;
  }

  Future<T> _write<T>(Future<T> Function() operation, {bool owner = false}) =>
      _access._base._writes.run(() async {
        await _access._validate(session);
        if (owner ? !isOwner : !canEdit) _deny();
        return runZoned(operation, zoneValues: {auditActorKey: staff.id});
      });

  Never _deny() =>
      throw const OfficeFailure('ليس لديك صلاحية لعرض البيانات أو تعديلها.');

  Expression<bool> _clientScope(Expression<String> clientId) {
    if (isOwner) return const Constant(true);
    return _assignedClientScope(clientId);
  }

  Expression<bool> _assignedClientScope(Expression<String> clientId) {
    final t = _db.clientLawyers;
    return existsQuery(
      _db.selectOnly(t)
        ..addColumns([t.id])
        ..where(
          t.clientId.equalsExp(clientId) &
              t.lawyerId.equals(staff.id) &
              t.endedAt.isNull() &
              t.deletedAt.isNull(),
        ),
    );
  }

  Expression<bool> _directCaseScope(Expression<String> caseId) {
    final t = _db.caseLawyers;
    return existsQuery(
      _db.selectOnly(t)
        ..addColumns([t.id])
        ..where(
          t.caseId.equalsExp(caseId) &
              t.lawyerId.equals(staff.id) &
              t.endedAt.isNull() &
              t.deletedAt.isNull(),
        ),
    );
  }

  Expression<bool> _caseScope(Cases c) =>
      c.deletedAt.isNull() &
      (_clientScope(c.clientId) | _directCaseScope(c.id));

  Future<CaseEntity> _case(String id) async {
    final row = await (_db.select(
      _db.cases,
    )..where((t) => t.id.equals(id) & _caseScope(t))).getSingleOrNull();
    return row ?? _deny();
  }

  Future<ClientEntity?> _fullClient(String id) =>
      (_db.select(_db.clients)..where(
            (t) => t.id.equals(id) & t.deletedAt.isNull() & _clientScope(t.id),
          ))
          .getSingleOrNull();

  Future<void> _needClient(String id) async {
    if (await _fullClient(id) == null) _deny();
  }

  ClientEntity _maskedClient(ClientEntity client) => ClientEntity(
    id: client.id,
    name: client.name,
    isArchived: client.isArchived,
    whatsappConsentStatus: 'UNKNOWN',
    createdAt: client.createdAt,
    revision: client.revision,
  );

  @override
  Future<void> initialize() async => _deny();

  @override
  Future<BackupResult> createBackup(Directory destinationRoot) =>
      _write(() => super.createBackup(destinationRoot), owner: true);

  Future<Directory> restoreBackupIsolated(
    Directory backup,
    Directory destination,
  ) => _write(
    () => BackupService().restoreIsolated(
      backup: backup,
      destination: destination,
    ),
    owner: true,
  );

  @override
  Future<String> addLawyer(String name) async => _deny();

  @override
  Future<List<OfficeLawyerEntity>> getLawyers() => _read(
    () async => isOwner
        ? (_db.select(
            _db.officeLawyers,
          )..where((t) => t.isActive & t.deletedAt.isNull())).get()
        : [staff],
  );

  @override
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) => _write(() async {
    if (!isOwner && lawyerId != null && lawyerId != staff.id) _deny();
    if (lawyerId != null && !(await _access._person(lawyerId)).isActive) {
      throw const OfficeFailure('المحامي المختار غير نشط.');
    }
    return super.addClient(
      name: name,
      phone: phone,
      lawyerId: isOwner ? lawyerId : staff.id,
    );
  });

  @override
  Future<void> updateClient(
    String id, {
    String? name,
    String? phone,
    String? lawyerId,
  }) => _write(() async {
    await _needClient(id);
    if (lawyerId != null) _deny();
    await super.updateClient(id, name: name, phone: phone);
  });

  @override
  Future<void> archiveClient(String id) => setArchived(id, true);

  @override
  Future<List<ClientEntity>> getActiveClients() => _read(
    () =>
        (_db.select(_db.clients)
              ..where(
                (t) =>
                    t.isArchived.equals(false) &
                    t.deletedAt.isNull() &
                    _clientScope(t.id),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get(),
  );

  @override
  Future<String> addCase({
    required String clientId,
    required String caseNumber,
    String? opponentName,
  }) => _write(() async {
    final client = await _fullClient(clientId);
    if (client == null || client.isArchived) _deny();
    return super.addCase(
      clientId: clientId,
      caseNumber: caseNumber,
      opponentName: opponentName,
    );
  });

  @override
  Future<List<CaseWithClient>> getCasesWithClients() =>
      _read(() => _caseList());

  Future<List<CaseWithClient>> myCases() => _read(() => _caseList(mine: true));

  Future<CaseWithClient> caseDetails(String id) => _read(() async {
    final rows = await _caseList(id: id, includeArchived: true);
    return rows.isEmpty ? _deny() : rows.single;
  });

  Future<List<CaseWithClient>> _caseList({
    String? id,
    bool includeArchived = false,
    bool mine = false,
  }) async {
    final c = _db.cases;
    final client = _db.clients;
    final full = _clientScope(client.id);
    final query = _db.select(c).join([
      innerJoin(client, client.id.equalsExp(c.clientId)),
    ]);
    query.addColumns([full]);
    query.where(
      _caseScope(c) &
          client.deletedAt.isNull() &
          (mine
              ? _assignedClientScope(client.id) | _directCaseScope(c.id)
              : const Constant(true)) &
          (includeArchived
              ? const Constant(true)
              : client.isArchived.equals(false)) &
          (id == null ? const Constant(true) : c.id.equals(id)),
    );
    query.orderBy([OrderingTerm.desc(c.createdAt)]);
    return (await query.get()).map((row) {
      final person = row.readTable(client);
      return CaseWithClient(
        caseEntity: row.readTable(c),
        client: row.read(full)! ? person : _maskedClient(person),
      );
    }).toList();
  }

  @override
  Future<void> updateCaseStatus(
    String caseId,
    String statusCode, {
    required String reason,
  }) => _write(() async {
    await _case(caseId);
    await super.updateCaseStatus(caseId, statusCode, reason: reason);
  });

  @override
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  }) => _write(() async {
    await _case(caseId);
    await super.addSession(
      caseId: caseId,
      sessionDate: sessionDate,
      courtLocation: courtLocation,
      circleNumber: circleNumber,
      decision: decision,
    );
  });

  @override
  Future<void> updateSessionDecision(
    String sessionId,
    String? decision, {
    required String reason,
  }) => _write(() async {
    final row =
        await (_db.select(_db.sessions)
              ..where((t) => t.id.equals(sessionId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) _deny();
    await _case(row.caseId);
    await super.updateSessionDecision(sessionId, decision, reason: reason);
  });

  Future<List<SessionWithDetails>> _agenda(int offset) => _read(() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + offset);
    final end = DateTime(now.year, now.month, now.day + offset + 1);
    final c = _db.cases;
    final clients = _db.clients;
    final s = _db.sessions;
    final full = _clientScope(clients.id);
    final query = _db.select(s).join([
      innerJoin(c, c.id.equalsExp(s.caseId)),
      innerJoin(clients, clients.id.equalsExp(c.clientId)),
    ]);
    query.addColumns([full]);
    query.where(
      _caseScope(c) &
          clients.deletedAt.isNull() &
          clients.isArchived.equals(false) &
          s.deletedAt.isNull() &
          s.sessionDate.isBiggerOrEqualValue(start) &
          s.sessionDate.isSmallerThanValue(end),
    );
    query.orderBy([OrderingTerm.asc(s.sessionDate)]);
    return (await query.get()).map((row) {
      final client = row.readTable(clients);
      return SessionWithDetails(
        session: row.readTable(s),
        caseEntity: row.readTable(c),
        client: row.read(full)! ? client : _maskedClient(client),
      );
    }).toList();
  });

  @override
  Future<List<SessionWithDetails>> getTodaySessions() => _agenda(0);
  @override
  Future<List<SessionWithDetails>> getTomorrowSessions() => _agenda(1);

  @override
  Future<List<SessionEntity>> getCaseSessions(String caseId) => _read(() async {
    await _case(caseId);
    return super.getCaseSessions(caseId);
  });

  @override
  Future<void> addCaseNote({required String caseId, required String content}) =>
      _write(() async {
        await _case(caseId);
        await super.addCaseNote(caseId: caseId, content: content);
      });

  @override
  Future<List<CaseNoteEntity>> getCaseNotes(String caseId) => _read(() async {
    await _case(caseId);
    return super.getCaseNotes(caseId);
  });

  @override
  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type,
    String? caseId,
    String? clientId,
  }) async => _deny();

  @override
  Future<List<TransactionEntity>> getAllTransactions() => _read(() async {
    if (!isOwner) _deny();
    return super.getAllTransactions();
  });

  @override
  Future<Map<String, double>> getTreasurySummary() => _read(() async {
    if (!isOwner) _deny();
    return super.getTreasurySummary();
  });

  @override
  Future<List<TransactionEntity>> getCaseTransactions(String caseId) =>
      _read(() async {
        final c = await _case(caseId);
        if (!canReadFinance) _deny();
        return (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.caseId.equals(caseId) &
                    (isOwner
                        ? const Constant(true)
                        : t.clientId.isNull() | t.clientId.equals(c.clientId)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
            .get();
      });

  @override
  Future<void> addCaseDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  }) => _write(() async {
    await _case(caseId);
    await super.addCaseDocument(
      caseId: caseId,
      title: title,
      filePath: filePath,
      fileType: fileType,
    );
  });

  @override
  Future<List<CaseDocumentEntity>> getCaseDocuments(String caseId) =>
      _read(() async {
        await _case(caseId);
        return super.getCaseDocuments(caseId);
      });

  @override
  Future<void> deleteCaseDocument(String id) => _write(() async {
    final d = await (_db.select(
      _db.caseDocuments,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (d == null) _deny();
    await _case(d.caseId);
    await super.deleteCaseDocument(id);
  });

  @override
  Future<String> resolveDocumentPath(String storedPath) => _read(() async {
    final d = _db.caseDocuments;
    final c = _db.cases;
    final query = _db.select(d).join([innerJoin(c, c.id.equalsExp(d.caseId))]);
    query.where(
      d.filePath.equals(storedPath) &
          d.deletedAt.isNull() &
          d.storageStatus.equals('AVAILABLE') &
          _caseScope(c),
    );
    query.limit(1);
    if ((await query.get()).isEmpty) _deny();
    return super.resolveDocumentPath(storedPath);
  });
}
