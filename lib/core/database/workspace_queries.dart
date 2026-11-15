part of 'app_repository.dart';

extension WorkspaceQueries on ScopedAppRepository {
  Future<List<StaffProfile>> team() => _read(() {
    if (!isOwner) _deny();
    return _access._profiles(activeOnly: false);
  });

  Future<String> saveStaff(
    StaffInput input, {
    String? id,
    String? initialPin,
    List<int>? photo,
    bool removePhoto = false,
  }) => _write(() async {
    final name = OfficeAccess._name(input.name);
    if (input.role == OfficeRole.owner && id != staff.id) _deny();
    if (photo != null && !_validPhoto(photo)) {
      throw const OfficeFailure(
        'اختر صورة JPEG أو PNG بحجم لا يتجاوز ٥١٢ كيلوبايت.',
      );
    }
    final hash = id == null
        ? await _access.hasher.hash(initialPin ?? '')
        : null;
    await _access._validate(session);
    return _db.transaction(() async {
      final previous = id == null ? null : await _access._person(id);
      if (previous?.role == OfficeRole.owner.code &&
          input.role != OfficeRole.owner) {
        _deny();
      }
      final personId = id ?? const Uuid().v4();
      final values = OfficeLawyersCompanion(
        name: Value(name),
        role: Value(input.role.code),
        phone: Value(_clean(input.phone)),
        email: Value(_clean(input.email)),
        barRegistrationNumber: Value(_clean(input.barNumber)),
        updatedAt: Value(_access._now),
        revision: Value((previous?.revision ?? 0) + 1),
      );
      if (previous == null) {
        await _db
            .into(_db.officeLawyers)
            .insert(values.copyWith(id: Value(personId)));
        await _access._storePin(personId, hash!, mustChange: true);
      } else {
        await (_db.update(
          _db.officeLawyers,
        )..where((t) => t.id.equals(personId))).write(values);
      }
      if (photo != null || removePhoto) {
        final settings = _db.appSettings;
        final saved =
            await (_db.select(settings)..where(
                  (t) =>
                      t.scopeOwnerId.equals(personId) &
                      t.key.equals('staff_photo') &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (saved != null) {
          await (_db.delete(
            settings,
          )..where((t) => t.id.equals(saved.id))).go();
        }
        if (photo != null) {
          await _db
              .into(settings)
              .insert(
                AppSettingsCompanion.insert(
                  id: const Uuid().v4(),
                  scopeOwnerId: Value(personId),
                  key: 'staff_photo',
                  valueJson: jsonEncode(base64Encode(photo)),
                ),
              );
        }
      }
      await recordChange(
        _db,
        entityType: 'STAFF',
        entityId: personId,
        action: previous == null ? 'CREATED' : 'UPDATED',
        reason: 'تحديث بيانات فريق المكتب',
        before: previous?.toJson(),
        after: (await _access._person(personId)).toJson(),
      );
      return personId;
    });
  }, owner: true);

  Future<void> setStaffActive(String id, bool active, String reason) =>
      _write(() async {
        final person = await _access._person(id);
        if (person.role == OfficeRole.owner.code) _deny();
        await _db.transaction(() async {
          await (_db.update(
            _db.officeLawyers,
          )..where((t) => t.id.equals(id))).write(
            OfficeLawyersCompanion(
              isActive: Value(active),
              revision: Value(person.revision + 1),
              updatedAt: Value(_access._now),
            ),
          );
          await recordChange(
            _db,
            entityType: 'STAFF',
            entityId: id,
            action: active ? 'ACTIVATED' : 'DEACTIVATED',
            reason: reason,
            before: {'active': person.isActive},
            after: {'active': active},
          );
        });
      }, owner: true);

  Future<void> resetStaffPin(
    String id,
    String ownerPin,
    String newPin,
    String reason,
  ) => _write(() async {
    final target = await _access._person(id);
    if (target.role == OfficeRole.owner.code) _deny();
    await _access._checkPin(staff.id, ownerPin);
    final hash = await _access.hasher.hash(newPin);
    await _access._validate(session);
    await _db.transaction(() async {
      await _access._storePin(id, hash, mustChange: true);
      await recordChange(
        _db,
        entityType: 'STAFF',
        entityId: id,
        action: 'PIN_RESET',
        reason: reason,
      );
    });
  }, owner: true);

  Future<void> setArchived(String clientId, bool archived) => _write(() async {
    final previous = await _fullClient(clientId);
    if (previous == null) _deny();
    await _db.transaction(() async {
      await (_db.update(
        _db.clients,
      )..where((t) => t.id.equals(clientId))).write(
        ClientsCompanion(
          isArchived: Value(archived),
          updatedAt: Value(_access._now),
          revision: Value(previous.revision + 1),
        ),
      );
      await recordChange(
        _db,
        entityType: 'CLIENT',
        entityId: clientId,
        action: archived ? 'ARCHIVED' : 'RESTORED',
        reason: archived ? 'أرشفة الموكل' : 'استعادة الموكل',
        before: {'archived': previous.isArchived},
        after: {'archived': archived},
      );
    });
  }, owner: true);

  Future<void> saveClientProfile(
    String clientId,
    ClientEdit edit,
  ) => _write(() async {
    final previous = await _fullClient(clientId);
    if (previous == null || previous.isArchived) _deny();
    if (!['UNKNOWN', 'GRANTED', 'WITHDRAWN'].contains(edit.consent)) {
      throw const OfficeFailure('اختر حالة موافقة صحيحة.');
    }
    final source = _clean(edit.consentSource);
    final consentChanged =
        edit.consent != previous.whatsappConsentStatus ||
        (edit.consent != 'UNKNOWN' && source != previous.consentSource);
    if (consentChanged && edit.consent != 'UNKNOWN' && source == null) {
      throw const OfficeFailure('سجّل مصدر الموافقة أو سحبها.');
    }
    if (previous.whatsappConsentStatus != 'UNKNOWN' &&
        edit.consent == 'UNKNOWN') {
      throw const OfficeFailure(
        'استخدم «سحب الموكل الموافقة» لتوثيق إيقاف التواصل.',
      );
    }
    final fields = edit.fields;
    final nationalId = _clean(fields['nationalId']);
    final normalizedId = nationalId == null
        ? null
        : PinHasher.normalize(nationalId);
    if (normalizedId != null &&
        !RegExp(r'^[0-9]{14}$').hasMatch(normalizedId)) {
      throw const OfficeFailure('الرقم القومي يجب أن يتكون من ١٤ رقمًا.');
    }
    await _db.transaction(() async {
      await (_db.update(
        _db.clients,
      )..where((t) => t.id.equals(clientId))).write(
        ClientsCompanion(
          name: Value(OfficeAccess._name(edit.name)),
          phone: Value(_clean(fields['phone'])),
          phoneSecondary: Value(_clean(fields['phoneSecondary'])),
          whatsappNumber: Value(_clean(fields['whatsappNumber'])),
          nationalId: Value(normalizedId),
          address: Value(_clean(fields['address'])),
          email: Value(_clean(fields['email'])),
          occupation: Value(_clean(fields['occupation'])),
          referralSource: Value(_clean(fields['referralSource'])),
          notes: Value(_clean(fields['notes'])),
          whatsappConsentStatus: Value(edit.consent),
          consentRecordedAt: consentChanged
              ? Value(_access._now)
              : const Value.absent(),
          consentRecordedBy: consentChanged
              ? Value(staff.id)
              : const Value.absent(),
          consentSource: consentChanged ? Value(source) : const Value.absent(),
          updatedAt: Value(_access._now),
          revision: Value(previous.revision + 1),
        ),
      );
      await recordChange(
        _db,
        entityType: 'CLIENT',
        entityId: clientId,
        action: 'PROFILE_UPDATED',
        reason: 'تحديث ملف الموكل',
        before: {'consent': previous.whatsappConsentStatus},
        after: {'consent': edit.consent, 'changedFields': fields.keys.toList()},
      );
    });
  });

  Future<ClientProfile> clientProfile(String id) => _read(() async {
    final full = await _fullClient(id);
    final c = _db.cases;
    final cases =
        await (_db.select(c)
              ..where((t) => t.clientId.equals(id) & _caseScope(t))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    if (full == null && cases.isEmpty) _deny();
    final person =
        full ??
        _maskedClient(
          await (_db.select(
            _db.clients,
          )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingle(),
        );
    final caseIds = cases.map((c) => c.id).toList();
    final sessions =
        await (_db.select(_db.sessions)
              ..where((t) => t.caseId.isIn(caseIds) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.sessionDate)]))
            .get();
    final notes =
        await (_db.select(_db.caseNotes)
              ..where((t) => t.caseId.isIn(caseIds) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    final docs =
        await (_db.select(_db.caseDocuments)
              ..where((t) => t.caseId.isIn(caseIds) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.uploadedAt)]))
            .get();
    List<TransactionEntity>? history;
    if (full != null && canReadFinance) {
      final t = _db.transactions;
      history =
          await (_db.select(t)
                ..where(
                  (t) =>
                      (t.caseId.isNull() & t.clientId.equals(id)) |
                      (t.caseId.isIn(caseIds) &
                          (isOwner
                              ? const Constant(true)
                              : t.clientId.isNull() | t.clientId.equals(id))),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
              .get();
    }
    return ClientProfile(
      client: person,
      fullAccess: full != null,
      cases: cases,
      sessions: sessions,
      notes: notes,
      documents: docs,
      assignments: full != null ? await _clientAssignments(id) : [],
      history: history,
    );
  });

  Future<List<AssignmentView>> assignments(
    String recordId, {
    required bool forCase,
  }) => _read(() async {
    if (forCase) {
      await _case(recordId);
      final t = _db.caseLawyers;
      final staff = _db.officeLawyers;
      final query = _db.select(t).join([
        innerJoin(staff, staff.id.equalsExp(t.lawyerId)),
      ]);
      query.where(t.caseId.equals(recordId) & t.deletedAt.isNull());
      query.orderBy([OrderingTerm.desc(t.createdAt)]);
      return (await query.get()).map((row) {
        final a = row.readTable(t);
        return AssignmentView(
          id: a.id,
          lawyerId: a.lawyerId,
          name: row.readTable(staff).name,
          role: a.assignmentRole,
          startedAt: a.startedAt,
          endedAt: a.endedAt,
          reason: a.changeReason,
        );
      }).toList();
    }
    await _needClient(recordId);
    return _clientAssignments(recordId);
  });

  Future<List<AssignmentView>> _clientAssignments(String id) async {
    final t = _db.clientLawyers;
    final staff = _db.officeLawyers;
    final query = _db.select(t).join([
      innerJoin(staff, staff.id.equalsExp(t.lawyerId)),
    ]);
    query.where(t.clientId.equals(id) & t.deletedAt.isNull());
    query.orderBy([OrderingTerm.desc(t.createdAt)]);
    return (await query.get()).map((row) {
      final a = row.readTable(t);
      return AssignmentView(
        id: a.id,
        lawyerId: a.lawyerId,
        name: row.readTable(staff).name,
        role: a.assignmentRole,
        startedAt: a.startedAt,
        endedAt: a.endedAt,
        reason: a.changeReason,
      );
    }).toList();
  }

  Future<void> assign(
    String recordId,
    String lawyerId, {
    required bool forCase,
    required String role,
    required String reason,
    bool replaceLead = false,
  }) => _write(() async {
    final target = await _access._person(lawyerId);
    if (!target.isActive) {
      throw const OfficeFailure('لا يمكن إسناد العمل لمستخدم غير نشط.');
    }
    if (reason.trim().isEmpty) throw const OfficeFailure('اكتب سبب الإسناد.');
    final now = _access._now;
    await _db.transaction(() async {
      final id = const Uuid().v4();
      final ended = <String>[];
      if (forCase) {
        await _case(recordId);
        if (!['LEAD', 'ASSISTANT'].contains(role)) _deny();
        final t = _db.caseLawyers;
        final active =
            await (_db.select(t)..where(
                  (t) =>
                      t.caseId.equals(recordId) &
                      t.endedAt.isNull() &
                      t.deletedAt.isNull(),
                ))
                .get();
        for (final row in active) {
          if (row.lawyerId == lawyerId && row.assignmentRole == role) {
            throw const OfficeFailure('هذا المستخدم مُسند بالفعل بهذا الدور.');
          }
          final replacing = role == 'LEAD' && row.assignmentRole == 'LEAD';
          if (replacing && !replaceLead) {
            throw const OfficeFailure(
              'يوجد محامٍ رئيسي. أكّد استبداله للمتابعة.',
            );
          }
          if (replacing || row.lawyerId == lawyerId) {
            await (_db.update(t)..where((t) => t.id.equals(row.id))).write(
              CaseLawyersCompanion(
                endedAt: Value(now),
                updatedAt: Value(now),
                changeReason: Value(reason.trim()),
                revision: Value(row.revision + 1),
              ),
            );
            ended.add(row.id);
          }
        }
        await _db
            .into(t)
            .insert(
              CaseLawyersCompanion.insert(
                id: id,
                caseId: recordId,
                lawyerId: lawyerId,
                assignmentRole: role,
                startedAt: Value(now),
                changeReason: Value(reason.trim()),
              ),
            );
      } else {
        await _needClient(recordId);
        final t = _db.clientLawyers;
        final duplicate =
            await (_db.select(t)..where(
                  (t) =>
                      t.clientId.equals(recordId) &
                      t.lawyerId.equals(lawyerId) &
                      t.endedAt.isNull() &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (duplicate != null) {
          throw const OfficeFailure('هذا المستخدم مُسند بالفعل.');
        }
        await _db
            .into(t)
            .insert(
              ClientLawyersCompanion.insert(
                id: id,
                clientId: recordId,
                lawyerId: lawyerId,
                startedAt: Value(now),
                changeReason: Value(reason.trim()),
              ),
            );
      }
      await recordChange(
        _db,
        entityType: forCase ? 'CASE_ASSIGNMENT' : 'CLIENT_ASSIGNMENT',
        entityId: recordId,
        action: 'ASSIGNED',
        reason: reason,
        before: {'ended': ended},
        after: {
          'assignment': id,
          'lawyer': lawyerId,
          'role': forCase ? role : 'RESPONSIBLE',
        },
      );
    });
  }, owner: true);

  Future<void> endAssignment(
    String recordId,
    String assignmentId, {
    required bool forCase,
    required String reason,
  }) => _write(
    () => _db.transaction(() async {
      final now = _access._now;
      if (forCase) {
        final t = _db.caseLawyers;
        final row =
            await (_db.select(t)..where(
                  (t) =>
                      t.id.equals(assignmentId) &
                      t.caseId.equals(recordId) &
                      t.endedAt.isNull() &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (row == null) _deny();
        await (_db.update(t)..where((t) => t.id.equals(assignmentId))).write(
          CaseLawyersCompanion(
            endedAt: Value(now),
            updatedAt: Value(now),
            changeReason: Value(reason.trim()),
            revision: Value(row.revision + 1),
          ),
        );
      } else {
        final t = _db.clientLawyers;
        final row =
            await (_db.select(t)..where(
                  (t) =>
                      t.id.equals(assignmentId) &
                      t.clientId.equals(recordId) &
                      t.endedAt.isNull() &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (row == null) _deny();
        await (_db.update(t)..where((t) => t.id.equals(assignmentId))).write(
          ClientLawyersCompanion(
            endedAt: Value(now),
            updatedAt: Value(now),
            changeReason: Value(reason.trim()),
            revision: Value(row.revision + 1),
          ),
        );
      }
      await recordChange(
        _db,
        entityType: forCase ? 'CASE_ASSIGNMENT' : 'CLIENT_ASSIGNMENT',
        entityId: recordId,
        action: 'ASSIGNMENT_ENDED',
        reason: reason,
        after: {'assignment': assignmentId},
      );
    }),
    owner: true,
  );

  Future<({List<ClientEntity> clients, int activeCases, int upcomingSessions})>
  workload(String lawyerId) => _read(() async {
    if (!isOwner) _deny();
    await _access._person(lawyerId);
    const clientLinks =
        'SELECT client_id FROM client_lawyers WHERE lawyer_id = ? AND ended_at IS NULL AND deleted_at IS NULL';
    final clients =
        await (_db.select(_db.clients)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  existsQuery(
                    _db.selectOnly(_db.clientLawyers)
                      ..addColumns([_db.clientLawyers.id])
                      ..where(
                        _db.clientLawyers.clientId.equalsExp(t.id) &
                            _db.clientLawyers.lawyerId.equals(lawyerId) &
                            _db.clientLawyers.endedAt.isNull() &
                            _db.clientLawyers.deletedAt.isNull(),
                      ),
                  ),
            ))
            .get();
    final row = await _db
        .customSelect(
          '''
      WITH assigned AS (
        SELECT c.id FROM cases c JOIN clients u ON u.id=c.client_id
        WHERE c.deleted_at IS NULL AND u.deleted_at IS NULL AND u.is_archived=0
          AND c.status_code IN ('ACTIVE','ON_HOLD')
          AND (c.client_id IN ($clientLinks) OR c.id IN (
            SELECT case_id FROM case_lawyers WHERE lawyer_id=? AND ended_at IS NULL AND deleted_at IS NULL))
      )
      SELECT (SELECT COUNT(*) FROM assigned) AS cases,
        (SELECT COUNT(*) FROM sessions WHERE deleted_at IS NULL AND session_date>=?
          AND case_id IN (SELECT id FROM assigned)) AS sessions
      ''',
          variables: [
            Variable(lawyerId),
            Variable(lawyerId),
            Variable(_access._now.millisecondsSinceEpoch ~/ 1000),
          ],
        )
        .getSingle();
    return (
      clients: clients,
      activeCases: row.read<int>('cases'),
      upcomingSessions: row.read<int>('sessions'),
    );
  });
}

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

bool _validPhoto(List<int> photo) {
  if (photo.length < 8 || photo.length > 512 * 1024) return false;
  return (photo[0] == 255 && photo[1] == 216 && photo[2] == 255) ||
      const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((e) => photo[e.key] == e.value);
}
