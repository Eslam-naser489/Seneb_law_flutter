part of 'app_repository.dart';

extension FinanceWorkspace on ScopedAppRepository {
  Future<void> rescheduleInstallment(
    String id, {
    required int expectedRevision,
    required String label,
    required DateTime dueAt,
    required int reminderDays,
    required String reason,
  }) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      _financeReason(label);
      final before = await (_db.select(
        _db.installments,
      )..where((t) => t.id.equals(id))).getSingle();
      await _ledger(before.chargeId);
      if (before.voidedAt != null ||
          before.revision != expectedRevision ||
          reminderDays < 0 ||
          reminderDays > 30) {
        throw const OfficeFailure(
          'راجع بيانات القسط؛ ربما تغيّر منذ فتح الصفحة.',
        );
      }
      await (_db.update(_db.installments)..where((t) => t.id.equals(id))).write(
        InstallmentsCompanion(
          label: Value(label.trim()),
          dueAt: Value(dueAt),
          reminderDays: Value(reminderDays),
          updatedAt: Value(DateTime.now()),
          revision: Value(before.revision + 1),
        ),
      );
      final after = await (_db.select(
        _db.installments,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'INSTALLMENT',
        entityId: id,
        action: 'RESCHEDULE',
        reason: reason,
        before: before.toJson(),
        after: after.toJson(),
      );
    }),
  );
  Future<void> enableInstallmentNotifications(bool enabled) => _write(
    () => _db.transaction(() async {
      final existing =
          await (_db.select(_db.appSettings)..where(
                (t) =>
                    t.key.equals('installment_notifications') &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final id = existing?.id ?? const Uuid().v4();
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              id: id,
              key: 'installment_notifications',
              valueJson: enabled ? 'true' : 'false',
              createdAt: existing == null
                  ? const Value.absent()
                  : Value(existing.createdAt),
              updatedAt: Value(DateTime.now()),
              revision: Value((existing?.revision ?? 0) + 1),
            ),
          );
      await recordChange(
        _db,
        entityType: 'SETTINGS',
        entityId: id,
        action: 'NOTIFICATIONS',
        reason: enabled ? 'تفعيل تذكيرات الأقساط' : 'إيقاف تذكيرات الأقساط',
        before: {'enabled': existing?.valueJson == 'true'},
        after: {'enabled': enabled},
      );
    }),
    owner: true,
  );
  Future<void> _financeClient(String clientId, {String? caseId}) async {
    if (!canReadFinance) _deny();
    await _needClient(clientId);
    if (caseId != null && (await _case(caseId)).clientId != clientId) {
      throw const OfficeFailure('القضية لا تخص هذا الموكل.');
    }
  }

  void _financeReason(String value) {
    if (value.trim().isEmpty || value.length > 2000) {
      throw const OfficeFailure(
        'أدخل بيانًا أو سببًا واضحًا لا يتجاوز ٢٠٠٠ حرف.',
      );
    }
  }

  Future<void> _validateEntry(LedgerInput input) async {
    await _financeClient(input.clientId, caseId: input.caseId);
    _financeReason(input.description);
    Money.fromMinor(input.amountMinor);
    if (!ledgerLabels.containsKey(input.kind) ||
        input.amountMinor == 0 ||
        (input.kind != 'ADJUSTMENT' && input.amountMinor < 0) ||
        input.amountMinor == -9223372036854775808) {
      throw const OfficeFailure('راجع نوع الحركة وقيمة المبلغ.');
    }
    if (['PAYMENT', 'REFUND', 'EXPENSE_ADVANCE'].contains(input.kind) &&
        !methodLabels.containsKey(input.paymentMethod)) {
      throw const OfficeFailure('اختر طريقة الدفع. الشيك يُسجل بعد تحصيله.');
    }
    if (!isOwner &&
        input.attributedLawyerId != null &&
        input.attributedLawyerId != staff.id) {
      _deny();
    }
    if (input.attributedLawyerId != null) {
      await _access._person(input.attributedLawyerId!);
    }
    if (input.occurredAt.isAfter(
      DateTime.now().add(const Duration(minutes: 5)),
    )) {
      throw const OfficeFailure('لا يمكن تسجيل حركة نقدية بتاريخ مستقبلي.');
    }
  }

  Future<ClientLedgerEntry> _ledger(String id) async {
    final e = await (_db.select(
      _db.clientLedgerEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (e == null) _deny();
    await _financeClient(e.clientId, caseId: e.caseId);
    return e;
  }

  Future<ClientAccount> clientAccount(String clientId) => _read(() async {
    await _financeClient(clientId);
    return _account(clientId);
  });

  Future<ClientAccount> _account(String clientId) async {
    final client = (await _fullClient(clientId))!;
    final cases = await (_db.select(
      _db.cases,
    )..where((t) => t.clientId.equals(clientId))).get();
    final entries =
        await (_db.select(_db.clientLedgerEntries)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.occurredAt),
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    final ids = entries.map((e) => e.id).toList();
    final agreements = await (_db.select(
      _db.feeAgreements,
    )..where((t) => t.caseId.isIn(cases.map((c) => c.id)))).get();
    final installments =
        await (_db.select(_db.installments)
              ..where((t) => t.chargeId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
            .get();
    final allocations = await (_db.select(
      _db.paymentAllocations,
    )..where((t) => t.chargeId.isIn(ids) | t.paymentId.isIn(ids))).get();
    final receipts =
        await (_db.select(_db.financialReceipts)
              ..where((t) => t.entryId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.desc(t.number)]))
            .get();
    return ClientAccount(
      client,
      entries,
      agreements,
      installments,
      allocations,
      receipts,
      cases,
    );
  }

  Future<String> postLedger(
    LedgerInput input, {
    required String operationKey,
  }) => _write(() => _db.transaction(() => _post(input, operationKey)));

  Future<String> _post(
    LedgerInput input,
    String operationKey, {
    String? agreementId,
  }) async {
    await _validateEntry(input);
    _financeReason(operationKey);
    final previous = await (_db.select(
      _db.clientLedgerEntries,
    )..where((t) => t.operationKey.equals(operationKey))).getSingleOrNull();
    if (previous != null) {
      if (previous.clientId != input.clientId ||
          previous.caseId != input.caseId ||
          previous.kind != input.kind ||
          previous.amountMinor != input.amountMinor ||
          previous.description != input.description.trim() ||
          previous.paymentMethod != input.paymentMethod ||
          previous.agreementId != agreementId ||
          previous.voidedAt != null) {
        throw const OfficeFailure('مفتاح الحفظ مستخدم لحركة مختلفة.');
      }
      return previous.id;
    }
    final id = const Uuid().v4();
    await _db
        .into(_db.clientLedgerEntries)
        .insert(
          ClientLedgerEntriesCompanion.insert(
            id: id,
            clientId: input.clientId,
            caseId: Value(input.caseId),
            kind: input.kind,
            amountMinor: input.amountMinor,
            description: input.description.trim(),
            paymentMethod: Value(input.paymentMethod),
            occurredAt: input.occurredAt,
            dueAt: Value(input.dueAt),
            agreementId: Value(agreementId),
            attributedLawyerId: input.attributedLawyerId ?? staff.id,
            createdBy: staff.id,
            operationKey: operationKey,
          ),
        );
    final after = await _ledger(id);
    // يرفض تجاوز المدى قبل اعتماد المعاملة، لا يجمع SQLite المبالغ كأرقام عائمة.
    await _checkAccountMoney(input.clientId);
    await recordChange(
      _db,
      entityType: 'LEDGER',
      entityId: id,
      action: 'CREATE',
      reason: input.description,
      after: after.toJson(),
    );
    return id;
  }

  Future<void> changeLedger(
    String id, {
    required int expectedRevision,
    required int amountMinor,
    required String description,
    required DateTime occurredAt,
    String? paymentMethod,
    DateTime? dueAt,
    required String reason,
    bool voidEntry = false,
  }) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      final before = await _ledger(id);
      if (before.revision != expectedRevision || before.voidedAt != null) {
        throw const OfficeFailure('تغيّرت الحركة. أعد تحميل الحساب.');
      }
      if (before.agreementId != null) {
        final agreement = await (_db.select(
          _db.feeAgreements,
        )..where((t) => t.id.equals(before.agreementId!))).getSingle();
        if (agreement.kind != 'HOURLY') {
          throw const OfficeFailure(
            'عدّل الأتعاب بإلغاء الاتفاق وجدولته من شاشة الاتفاق.',
          );
        }
      }
      await _assertUnallocated(id);
      final receipt =
          await (_db.select(_db.financialReceipts)
                ..where((t) => t.entryId.equals(id) & t.voidedAt.isNull()))
              .getSingleOrNull();
      if (receipt != null && !voidEntry) {
        throw const OfficeFailure(
          'الحركة لها إيصال صادر. ألغِ الحركة والإيصال ثم سجّل البديل.',
        );
      }
      if (!voidEntry) {
        await _validateEntry(
          LedgerInput(
            clientId: before.clientId,
            caseId: before.caseId,
            kind: before.kind,
            amountMinor: amountMinor,
            description: description,
            occurredAt: occurredAt,
            paymentMethod: paymentMethod,
            dueAt: dueAt,
          ),
        );
      }
      final now = DateTime.now();
      await (_db.update(
        _db.clientLedgerEntries,
      )..where((t) => t.id.equals(id))).write(
        ClientLedgerEntriesCompanion(
          amountMinor: Value(voidEntry ? before.amountMinor : amountMinor),
          description: Value(
            voidEntry ? before.description : description.trim(),
          ),
          occurredAt: Value(voidEntry ? before.occurredAt : occurredAt),
          paymentMethod: Value(
            voidEntry ? before.paymentMethod : paymentMethod,
          ),
          dueAt: Value(voidEntry ? before.dueAt : dueAt),
          voidedAt: Value(voidEntry ? now : null),
          voidReason: Value(voidEntry ? reason.trim() : null),
          updatedAt: Value(now),
          revision: Value(before.revision + 1),
        ),
      );
      if (receipt != null) await _voidReceipt(receipt, reason);
      await _checkAccountMoney(before.clientId);
      await recordChange(
        _db,
        entityType: 'LEDGER',
        entityId: id,
        action: voidEntry ? 'VOID' : 'EDIT',
        reason: reason,
        before: before.toJson(),
        after: (await _ledger(id)).toJson(),
      );
    }),
  );

  Future<void> _assertUnallocated(String id) async {
    final rows =
        await (_db.select(_db.paymentAllocations)..where(
              (t) =>
                  (t.paymentId.equals(id) | t.chargeId.equals(id)) &
                  t.voidedAt.isNull(),
            ))
            .get();
    if (rows.isNotEmpty) {
      throw const OfficeFailure(
        'ألغِ تخصيصات السداد المرتبطة أولًا، ثم صحّح الحركة.',
      );
    }
  }

  Future<void> _checkAccountMoney(String clientId) async {
    final account = await _account(clientId);
    account.balance;
    if (account.refundableCash < 0) {
      throw const OfficeFailure(
        'رد المبلغ يتجاوز الدفعات غير المخصصة. ألغِ تخصيص الجزء المراد رده أولًا؛ الخصم والتسوية لا يمثلان نقدًا قابلًا للرد.',
      );
    }
  }

  Future<String> allocatePayment({
    required String paymentId,
    required String chargeId,
    String? installmentId,
    required int amountMinor,
    required String reason,
    required String operationKey,
  }) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      if (amountMinor <= 0) {
        throw const OfficeFailure('أدخل قيمة موجبة للتخصيص.');
      }
      final payment = await _ledger(paymentId),
          charge = await _ledger(chargeId);
      if (!isCredit(payment) ||
          !isCharge(charge) ||
          payment.clientId != charge.clientId ||
          (payment.caseId != null && payment.caseId != charge.caseId)) {
        throw const OfficeFailure(
          'التخصيص يجب أن يطابق الموكل والقضية وحركة سارية.',
        );
      }
      final previous = await (_db.select(
        _db.paymentAllocations,
      )..where((t) => t.operationKey.equals(operationKey))).getSingleOrNull();
      if (previous != null) {
        if (previous.paymentId != paymentId ||
            previous.chargeId != chargeId ||
            previous.installmentId != installmentId ||
            previous.amountMinor != amountMinor ||
            previous.voidedAt != null) {
          throw const OfficeFailure('عملية التخصيص سبق استخدامها.');
        }
        return previous.id;
      }
      final account = await _account(payment.clientId);
      if (payment.kind == 'PAYMENT' && amountMinor > account.refundableCash) {
        throw const OfficeFailure(
          'جزء من الرصيد أُعيد للموكل ولا يمكن تخصيصه مجددًا.',
        );
      }
      if (amountMinor >
              payment.amountMinor.abs() - account.allocated(paymentId) ||
          amountMinor > charge.amountMinor - account.allocated(chargeId)) {
        throw const OfficeFailure('التخصيص يتجاوز المبلغ المتاح أو المستحق.');
      }
      final schedule = account.installments
          .where((i) => i.chargeId == chargeId && i.voidedAt == null)
          .toList();
      if (schedule.isNotEmpty && installmentId == null) {
        throw const OfficeFailure('اختر القسط الذي تسدده.');
      }
      if (installmentId != null) {
        final matching = schedule.where((i) => i.id == installmentId);
        if (matching.isEmpty ||
            amountMinor > account.installmentRemaining(matching.single)) {
          throw const OfficeFailure('القسط غير صالح أو تم سداد قيمته.');
        }
      }
      final id = const Uuid().v4();
      await _db
          .into(_db.paymentAllocations)
          .insert(
            PaymentAllocationsCompanion.insert(
              id: id,
              paymentId: paymentId,
              chargeId: chargeId,
              installmentId: Value(installmentId),
              amountMinor: amountMinor,
              createdBy: staff.id,
              operationKey: operationKey,
            ),
          );
      final row = await (_db.select(
        _db.paymentAllocations,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'ALLOCATION',
        entityId: id,
        action: 'CREATE',
        reason: reason,
        after: row.toJson(),
      );
      return id;
    }),
  );

  Future<void> voidAllocation(String id, String reason) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      final before = await (_db.select(
        _db.paymentAllocations,
      )..where((t) => t.id.equals(id))).getSingle();
      await _ledger(before.paymentId);
      await _ledger(before.chargeId);
      if (before.voidedAt != null) {
        throw const OfficeFailure('التخصيص ملغى بالفعل.');
      }
      await (_db.update(
        _db.paymentAllocations,
      )..where((t) => t.id.equals(id))).write(
        PaymentAllocationsCompanion(
          voidedAt: Value(DateTime.now()),
          voidReason: Value(reason),
          updatedAt: Value(DateTime.now()),
          revision: Value(before.revision + 1),
        ),
      );
      final after = await (_db.select(
        _db.paymentAllocations,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'ALLOCATION',
        entityId: id,
        action: 'VOID',
        reason: reason,
        before: before.toJson(),
        after: after.toJson(),
      );
    }),
  );

  Future<String> createAgreement({
    required String caseId,
    required String kind,
    required int amountMinor,
    required String terms,
    required List<InstallmentInput> schedule,
    required String operationKey,
  }) => _write(
    () => _db.transaction(() async {
      final c = await _case(caseId);
      await _financeClient(c.clientId, caseId: caseId);
      _financeReason(terms);
      if (!agreementLabels.containsKey(kind) || amountMinor <= 0) {
        throw const OfficeFailure(
          'اختر اتفاقًا بقيمة موجبة. أتعاب النسبة والنجاح تحتاج تحققًا قانونيًا وهي غير مفعلة.',
        );
      }
      Money.fromMinor(amountMinor);
      if (kind == 'HOURLY' && schedule.isNotEmpty) {
        throw const OfficeFailure('تُجدول أتعاب الساعة بعد إثبات العمل.');
      }
      if (kind != 'HOURLY' &&
          (schedule.isEmpty ||
              checkedSum(schedule.map((i) => i.amountMinor)) != amountMinor)) {
        throw const OfficeFailure('مجموع الأقساط يجب أن يساوي إجمالي الأتعاب.');
      }
      for (final i in schedule) {
        _financeReason(i.label);
        if (i.amountMinor <= 0 || i.reminderDays < 0 || i.reminderDays > 30) {
          throw const OfficeFailure('راجع مبالغ الأقساط وأيام التذكير.');
        }
      }
      final id = const Uuid().v4();
      await _db
          .into(_db.feeAgreements)
          .insert(
            FeeAgreementsCompanion.insert(
              id: id,
              caseId: caseId,
              kind: kind,
              amountMinor: amountMinor,
              terms: terms.trim(),
              createdBy: staff.id,
              operationKey: operationKey,
            ),
          );
      if (kind != 'HOURLY') {
        final charge = await _post(
          LedgerInput(
            clientId: c.clientId,
            caseId: caseId,
            kind: 'FEE',
            amountMinor: amountMinor,
            description: terms,
            occurredAt: DateTime.now(),
          ),
          '$operationKey/fee',
          agreementId: id,
        );
        for (final i in schedule) {
          await _db
              .into(_db.installments)
              .insert(
                InstallmentsCompanion.insert(
                  id: const Uuid().v4(),
                  agreementId: id,
                  chargeId: charge,
                  label: i.label.trim(),
                  amountMinor: i.amountMinor,
                  dueAt: i.dueAt,
                  reminderDays: Value(i.reminderDays),
                  createdBy: staff.id,
                ),
              );
        }
      }
      final after = await (_db.select(
        _db.feeAgreements,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'AGREEMENT',
        entityId: id,
        action: 'CREATE',
        reason: terms,
        after: {
          ...after.toJson(),
          'schedule': schedule
              .map(
                (i) => {
                  'label': i.label,
                  'amountMinor': i.amountMinor,
                  'dueAt': i.dueAt.toIso8601String(),
                  'reminderDays': i.reminderDays,
                },
              )
              .toList(),
        },
      );
      return id;
    }),
  );

  Future<String> accrueHours(
    String agreementId,
    int minutes,
    String description,
    DateTime dueAt,
    String operationKey,
  ) => _write(
    () => _db.transaction(() async {
      final agreement = await (_db.select(
        _db.feeAgreements,
      )..where((t) => t.id.equals(agreementId))).getSingle();
      final c = await _case(agreement.caseId);
      await _financeClient(c.clientId);
      if (agreement.kind != 'HOURLY' ||
          agreement.voidedAt != null ||
          minutes <= 0 ||
          minutes > 1000000) {
        throw const OfficeFailure('راجع اتفاق الساعة والدقائق.');
      }
      final product = BigInt.from(agreement.amountMinor) * BigInt.from(minutes);
      final rounded = (product + BigInt.from(30)) ~/ BigInt.from(60);
      if (rounded > BigInt.from(9223372036854775807)) {
        throw const OfficeFailure('المبلغ خارج النطاق.');
      }
      return _post(
        LedgerInput(
          clientId: c.clientId,
          caseId: c.id,
          kind: 'FEE',
          amountMinor: rounded.toInt(),
          description:
              '$description — $minutes دقيقة؛ سعر الساعة ${moneyText(agreement.amountMinor)}؛ التقريب لأقرب قرش',
          occurredAt: DateTime.now(),
          dueAt: dueAt,
        ),
        operationKey,
        agreementId: agreementId,
      );
    }),
  );

  Future<void> voidAgreement(String id, String reason) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      final before = await (_db.select(
        _db.feeAgreements,
      )..where((t) => t.id.equals(id))).getSingle();
      final c = await _case(before.caseId);
      await _financeClient(c.clientId);
      if (before.voidedAt != null) {
        throw const OfficeFailure('الاتفاق ملغى بالفعل.');
      }
      final rows = await (_db.select(
        _db.clientLedgerEntries,
      )..where((t) => t.agreementId.equals(id) & t.voidedAt.isNull())).get();
      for (final e in rows) {
        await _assertUnallocated(e.id);
        await (_db.update(
          _db.clientLedgerEntries,
        )..where((t) => t.id.equals(e.id))).write(
          ClientLedgerEntriesCompanion(
            voidedAt: Value(DateTime.now()),
            voidReason: Value(reason),
            updatedAt: Value(DateTime.now()),
            revision: Value(e.revision + 1),
          ),
        );
        await recordChange(
          _db,
          entityType: 'LEDGER',
          entityId: e.id,
          action: 'VOID',
          reason: reason,
          before: e.toJson(),
          after: (await _ledger(e.id)).toJson(),
        );
      }
      final installments = await (_db.select(
        _db.installments,
      )..where((t) => t.agreementId.equals(id) & t.voidedAt.isNull())).get();
      for (final i in installments) {
        await (_db.update(
          _db.installments,
        )..where((t) => t.id.equals(i.id))).write(
          InstallmentsCompanion(
            voidedAt: Value(DateTime.now()),
            voidReason: Value(reason),
            updatedAt: Value(DateTime.now()),
            revision: Value(i.revision + 1),
          ),
        );
      }
      await (_db.update(
        _db.feeAgreements,
      )..where((t) => t.id.equals(id))).write(
        FeeAgreementsCompanion(
          voidedAt: Value(DateTime.now()),
          voidReason: Value(reason),
          updatedAt: Value(DateTime.now()),
          revision: Value(before.revision + 1),
        ),
      );
      final after = await (_db.select(
        _db.feeAgreements,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'AGREEMENT',
        entityId: id,
        action: 'VOID',
        reason: reason,
        before: {
          ...before.toJson(),
          'installments': installments.map((i) => i.toJson()).toList(),
        },
        after: after.toJson(),
      );
    }),
  );

  Future<FinancialReceipt> issueReceipt(String entryId) => _write(
    () => _db.transaction(() async {
      final e = await _ledger(entryId);
      if (e.voidedAt != null || !['PAYMENT', 'REFUND'].contains(e.kind)) {
        throw const OfficeFailure('الإيصال متاح للدفعة أو الرد الساري فقط.');
      }
      final existing =
          await (_db.select(_db.financialReceipts)
                ..where((t) => t.entryId.equals(entryId) & t.voidedAt.isNull()))
              .getSingleOrNull();
      if (existing != null) return existing;
      final client = (await _fullClient(e.clientId))!;
      final c = e.caseId == null ? null : await _case(e.caseId!);
      final id = const Uuid().v4();
      final snapshot = {
        'clientName': client.name,
        'caseNumber': c?.caseNumber,
        'entry': e.toJson(),
        'issuer': staff.name,
        'currency': 'EGP',
      };
      final number = await _db
          .into(_db.financialReceipts)
          .insert(
            FinancialReceiptsCompanion.insert(
              id: id,
              entryId: entryId,
              snapshotJson: jsonEncode(snapshot),
              createdBy: staff.id,
            ),
          );
      final receipt = await (_db.select(
        _db.financialReceipts,
      )..where((t) => t.number.equals(number))).getSingle();
      await recordChange(
        _db,
        entityType: 'RECEIPT',
        entityId: id,
        action: 'ISSUE',
        reason: 'إصدار إيصال مرقم',
        after: receipt.toJson(),
      );
      return receipt;
    }),
  );

  Future<FinancialReceipt> readReceipt(int number) => _read(() async {
    final receipt = await (_db.select(
      _db.financialReceipts,
    )..where((t) => t.number.equals(number))).getSingle();
    await _ledger(receipt.entryId);
    return receipt;
  });

  Future<void> _voidReceipt(FinancialReceipt r, String reason) async {
    await (_db.update(
      _db.financialReceipts,
    )..where((t) => t.number.equals(r.number))).write(
      FinancialReceiptsCompanion(
        voidedAt: Value(DateTime.now()),
        voidReason: Value(reason),
      ),
    );
    final after = await (_db.select(
      _db.financialReceipts,
    )..where((t) => t.number.equals(r.number))).getSingle();
    await recordChange(
      _db,
      entityType: 'RECEIPT',
      entityId: r.id,
      action: 'VOID',
      reason: reason,
      before: r.toJson(),
      after: after.toJson(),
    );
  }

  Future<String> saveOfficeExpense({
    String? id,
    int? expectedRevision,
    required int amountMinor,
    required String description,
    required String category,
    required String paymentMethod,
    required DateTime occurredAt,
    required String reason,
    required String operationKey,
    bool voidEntry = false,
  }) => _write(
    () => _db.transaction(
      () => _officeExpense(
        id: id,
        expectedRevision: expectedRevision,
        amountMinor: amountMinor,
        description: description,
        category: category,
        paymentMethod: paymentMethod,
        occurredAt: occurredAt,
        reason: reason,
        operationKey: operationKey,
        voidEntry: voidEntry,
      ),
    ),
    owner: true,
  );

  Future<String> _officeExpense({
    String? id,
    int? expectedRevision,
    required int amountMinor,
    required String description,
    required String category,
    required String paymentMethod,
    required DateTime occurredAt,
    required String reason,
    required String operationKey,
    bool voidEntry = false,
  }) async {
    _financeReason(reason);
    _financeReason(description);
    _financeReason(category);
    Money.fromMinor(amountMinor);
    if (amountMinor <= 0 ||
        !methodLabels.containsKey(paymentMethod) ||
        occurredAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const OfficeFailure('راجع مبلغ المصروف وطريقة الدفع والتاريخ.');
    }
    OfficeExpense? before;
    if (id != null) {
      before = await (_db.select(
        _db.officeExpenses,
      )..where((t) => t.id.equals(id!))).getSingle();
      if (before.revision != expectedRevision || before.voidedAt != null) {
        throw const OfficeFailure('تغيّر المصروف. أعد تحميل الصفحة.');
      }
      await (_db.update(
        _db.officeExpenses,
      )..where((t) => t.id.equals(id!))).write(
        OfficeExpensesCompanion(
          amountMinor: Value(voidEntry ? before.amountMinor : amountMinor),
          description: Value(
            voidEntry ? before.description : description.trim(),
          ),
          category: Value(voidEntry ? before.category : category.trim()),
          paymentMethod: Value(
            voidEntry ? before.paymentMethod : paymentMethod,
          ),
          occurredAt: Value(voidEntry ? before.occurredAt : occurredAt),
          voidedAt: Value(voidEntry ? DateTime.now() : null),
          voidReason: Value(voidEntry ? reason : null),
          updatedAt: Value(DateTime.now()),
          revision: Value(before.revision + 1),
        ),
      );
    } else {
      if (voidEntry) throw const OfficeFailure('لا يمكن إلغاء مصروف غير مسجل.');
      id = const Uuid().v4();
      await _db
          .into(_db.officeExpenses)
          .insert(
            OfficeExpensesCompanion.insert(
              id: id,
              amountMinor: amountMinor,
              description: description.trim(),
              category: category.trim(),
              paymentMethod: paymentMethod,
              occurredAt: occurredAt,
              createdBy: staff.id,
              operationKey: operationKey,
            ),
          );
    }
    final after = await (_db.select(
      _db.officeExpenses,
    )..where((t) => t.id.equals(id!))).getSingle();
    await recordChange(
      _db,
      entityType: 'OFFICE_EXPENSE',
      entityId: id,
      action: voidEntry
          ? 'VOID'
          : before == null
          ? 'CREATE'
          : 'EDIT',
      reason: reason,
      before: before?.toJson(),
      after: after.toJson(),
    );
    return id;
  }

  Future<FinanceDashboard> financeDashboard() => _read(() async {
    if (!isOwner) _deny();
    final clients = await (_db.select(
      _db.clients,
    )..where((t) => t.deletedAt.isNull())).get();
    final accounts = <ClientAccount>[];
    for (final client in clients) {
      accounts.add(await _account(client.id));
    }
    final expenses = await (_db.select(
      _db.officeExpenses,
    )..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).get();
    final pending = await (_db.select(
      _db.legacyTransactionReviews,
    )..where((t) => t.reviewStatus.equals('PENDING'))).get();
    return FinanceDashboard(
      accounts: accounts,
      expenses: expenses,
      pendingLegacy: pending.length,
    );
  });

  Future<List<LegacyReviewItem>> legacyReviews() => _read(() async {
    if (!isOwner) _deny();
    final reviews = await _db.select(_db.legacyTransactionReviews).get();
    final sources = {
      for (final s in await _db.select(_db.transactions).get()) s.id: s,
    };
    final classifications = {
      for (final c in await _db.select(_db.legacyClassifications).get())
        c.reviewId: c,
    };
    return reviews
        .map(
          (r) => LegacyReviewItem(
            r,
            sources[r.legacyTransactionId]!,
            classifications[r.id],
          ),
        )
        .toList();
  });

  Future<void> classifyLegacy(
    String reviewId, {
    required String destination,
    required String reason,
    LedgerInput? ledger,
    int? amountMinor,
    String? category,
    String? paymentMethod,
    String? officeDescription,
    DateTime? officeOccurredAt,
  }) => _write(
    () => _db.transaction(() async {
      _financeReason(reason);
      if (!['LEDGER', 'OFFICE', 'EXCLUDE'].contains(destination)) {
        throw const OfficeFailure('اختر تصنيفًا صالحًا.');
      }
      final review = await (_db.select(
        _db.legacyTransactionReviews,
      )..where((t) => t.id.equals(reviewId))).getSingle();
      if (review.reviewStatus != 'PENDING') {
        throw const OfficeFailure(
          'تمت مراجعة هذه الحركة بالفعل. التصحيح من الدفتر مع سبب.',
        );
      }
      final source = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(review.legacyTransactionId))).getSingle();
      String? ledgerId, expenseId;
      if (destination == 'LEDGER') {
        if (ledger == null) {
          throw const OfficeFailure('اختر الموكل ونوع الحركة والمبلغ الصحيح.');
        }
        ledgerId = await _post(ledger, 'legacy/$reviewId');
      } else if (destination == 'OFFICE') {
        if (amountMinor == null || category == null || paymentMethod == null) {
          throw const OfficeFailure('راجع بيانات المصروف.');
        }
        expenseId = await _officeExpense(
          amountMinor: amountMinor,
          description: officeDescription ?? source.title,
          category: category,
          paymentMethod: paymentMethod,
          occurredAt: officeOccurredAt ?? source.transactionDate,
          reason: reason,
          operationKey: 'legacy/$reviewId',
        );
      }
      final id = const Uuid().v4();
      await _db
          .into(_db.legacyClassifications)
          .insert(
            LegacyClassificationsCompanion.insert(
              id: id,
              reviewId: reviewId,
              destination: destination,
              ledgerEntryId: Value(ledgerId),
              officeExpenseId: Value(expenseId),
              reason: reason,
              reviewedBy: staff.id,
            ),
          );
      await (_db.update(
        _db.legacyTransactionReviews,
      )..where((t) => t.id.equals(reviewId))).write(
        LegacyTransactionReviewsCompanion(
          reviewStatus: Value(
            destination == 'EXCLUDE' ? 'EXCLUDED' : 'CLASSIFIED',
          ),
          reviewedBy: Value(staff.id),
          reviewedAt: Value(DateTime.now()),
        ),
      );
      final classification = await (_db.select(
        _db.legacyClassifications,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        _db,
        entityType: 'LEGACY_REVIEW',
        entityId: reviewId,
        action: 'CLASSIFY',
        reason: reason,
        before: {'source': source.toJson(), 'review': review.toJson()},
        after: classification.toJson(),
      );
    }),
    owner: true,
  );

  Future<List<AuditLogData>> financialHistory(String entityType, String id) =>
      _read(() async {
        if (entityType == 'LEDGER') {
          await _ledger(id);
        } else if (entityType == 'INSTALLMENT') {
          final installment = await (_db.select(
            _db.installments,
          )..where((t) => t.id.equals(id))).getSingle();
          await _ledger(installment.chargeId);
        } else if (!isOwner) {
          _deny();
        }
        return (_db.select(_db.auditLog)
              ..where(
                (t) => t.entityType.equals(entityType) & t.entityId.equals(id),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
      });
}
