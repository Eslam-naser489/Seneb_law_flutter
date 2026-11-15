part of 'app_repository.dart';

extension ReportWorkspace on ScopedAppRepository {
  Future<Map<String, dynamic>> reportBranding() => _read(_reportBranding);
  Future<Map<String, dynamic>> _reportBranding() async {
    final row =
        await (_db.select(_db.appSettings)..where(
              (t) =>
                  t.key.equals('office_branding') &
                  t.scopeOwnerId.isNull() &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null
        ? {'name': 'مكتب المحاماة', 'logo': null}
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
  }

  Future<void> saveReportBranding(String name, Uint8List? logo) => _write(
    () => _db.transaction(() async {
      if (name.trim().isEmpty ||
          name.length > 150 ||
          (logo?.length ?? 0) > 1000000) {
        throw const OfficeFailure(
          'أدخل اسم المكتب، واختر شعار PNG أو JPEG لا يزيد على ١ ميجابايت.',
        );
      }
      if (logo != null &&
          !(logo.length > 8 &&
              ((logo[0] == 137 &&
                      logo[1] == 80 &&
                      logo[2] == 78 &&
                      logo[3] == 71) ||
                  (logo[0] == 255 && logo[1] == 216 && logo[2] == 255)))) {
        throw const OfficeFailure('الشعار يجب أن يكون صورة PNG أو JPEG.');
      }
      final existing =
          await (_db.select(_db.appSettings)..where(
                (t) =>
                    t.key.equals('office_branding') &
                    t.scopeOwnerId.isNull() &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final id = existing?.id ?? const Uuid().v4();
      final value = jsonEncode({
        'name': name.trim(),
        'logo': logo == null ? null : base64Encode(logo),
      });
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              id: id,
              key: 'office_branding',
              valueJson: value,
              createdAt: existing == null
                  ? const Value.absent()
                  : Value(existing.createdAt),
              updatedAt: Value(_access._now),
              revision: Value((existing?.revision ?? 0) + 1),
            ),
          );
      await recordChange(
        _db,
        entityType: 'SETTINGS',
        entityId: id,
        action: 'BRANDING',
        reason: 'تحديث هوية المكتب',
        before: {
          'name': existing == null
              ? null
              : jsonDecode(existing.valueJson)['name'],
        },
        after: {'name': name.trim(), 'hasLogo': logo != null},
      );
    }),
    owner: true,
  );

  Future<List<ReportTemplate>> reportTemplates() => _read(
    () => (_db.select(
      _db.reportTemplates,
    )..where((t) => t.isActive & t.deletedAt.isNull())).get(),
  );

  Future<ReportContext> reportContext(String caseId) => _read(() async {
    if (!canEdit) _deny();
    final c = await _case(caseId);
    final client =
        await (_db.select(_db.clients)
              ..where((t) => t.id.equals(c.clientId) & t.deletedAt.isNull()))
            .getSingle();
    final full = await _fullClient(c.clientId);
    final sessions =
        await (_db.select(_db.sessions)
              ..where((t) => t.caseId.equals(caseId) & t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm.asc(t.sessionDate),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    final now = _access._now;
    final past = sessions
        .where(
          (s) =>
              !s.sessionDate.isAfter(now) &&
              (s.decision?.trim().isNotEmpty ?? false),
        )
        .toList();
    final next = sessions
        .where(
          (s) =>
              !s.sessionDate.isBefore(DateTime(now.year, now.month, now.day)),
        )
        .firstOrNull;
    final notes =
        await (_db.select(_db.caseNotes)
              ..where(
                (t) =>
                    t.caseId.equals(caseId) &
                    t.deletedAt.isNull() &
                    t.visibility.equals('CLIENT_ELIGIBLE'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return ReportContext(
      clientId: c.clientId,
      caseId: caseId,
      clientName: client.name,
      financeAllowed: full != null && canReadFinance,
      recipient: full?.whatsappNumber ?? full?.phone ?? '',
      consent: full?.whatsappConsentStatus ?? 'UNKNOWN',
      eligibleNotes: notes,
      defaults: {
        'summary':
            'حالة القضية: ${c.status}${c.opponentName == null ? '' : '\nالخصم: ${c.opponentName}'}',
        if (past.isNotEmpty)
          'development':
              '${reportDate(past.last.sessionDate)}: ${past.last.decision}',
        if (next != null)
          'nextSession':
              '${reportDate(next.sessionDate)}\nالمحكمة: ${next.courtLocation}\nالدائرة: ${next.circleNumber ?? 'غير مسجلة'}',
      },
    );
  });

  Future<PreparedReport> prepareReport(
    ReportRequest request, {
    DateTime? createdAt,
  }) => _read(() async {
    if (!canEdit || !['REPORT', 'RECEIPT', 'STATEMENT'].contains(request.kind)) {
      _deny();
    }
    if (request.kind == 'STATEMENT' && request.caseId != null) {
      throw const OfficeFailure(
        'كشف الحساب يعرض حساب الموكل كاملًا؛ اختر كشف الموكل.',
      );
    }
    CaseEntity? c;
    if (request.caseId != null) {
      c = await _case(request.caseId!);
      if (c.clientId != request.clientId) _deny();
    } else if (request.kind == 'REPORT') {
      _deny();
    }
    if (request.kind != 'REPORT' || request.includeFinance) {
      await _financeClient(request.clientId, caseId: request.caseId);
    } else if (c == null) {
      await _needClient(request.clientId);
    }
    final client =
        await (_db.select(_db.clients)..where(
              (t) => t.id.equals(request.clientId) & t.deletedAt.isNull(),
            ))
            .getSingle();
    if (client.isArchived) {
      throw const OfficeFailure('الموكل مؤرشف؛ استعده قبل إعداد تقرير جديد.');
    }
    final brand = await _reportBranding();
    final actor = await _access._person(staff.id);
    final time = createdAt ?? _access._now;
    final sections = <Map<String, String>>[];
    final source = <Object?>[
      client.revision,
      c?.revision,
      brand,
      actor.toJson(),
    ];
    final financial = request.includeFinance || request.kind != 'REPORT';
    String title = 'تقرير تقدم القضية';
    if (request.kind == 'REPORT') {
      final sessions = await (_db.select(
        _db.sessions,
      )..where((t) => t.caseId.equals(c!.id))).get();
      source.add(sessions.map((s) => s.toJson()).toList());
      for (final entry in request.sections.entries) {
        if (!reportSectionLabels.containsKey(entry.key) ||
            entry.key == 'finance' ||
            entry.value.trim().isEmpty ||
            entry.value.length > 10000 ||
            RegExp(r'\{\{.*?\}\}').hasMatch(entry.value)) {
          throw const OfficeFailure(
            'أكمل الأقسام المحددة أو ألغِ اختيارها؛ لا تترك حقول قالب فارغة.',
          );
        }
      }
      for (final key in reportSectionLabels.keys.where(
        (k) => request.sections.containsKey(k),
      )) {
        sections.add({
          'label': reportSectionLabels[key]!,
          'text': request.sections[key]!.trim(),
        });
      }
    }
    if (financial) {
      final account = await _account(request.clientId);
      source.addAll([
        account.entries.map((e) => e.toJson()).toList(),
        account.allocations.map((e) => e.toJson()).toList(),
      ]);
      final pending = await (_db.select(
        _db.legacyTransactionReviews,
      )..where((t) => t.reviewStatus.equals('PENDING'))).get();
      source.add(pending.map((e) => e.id).toList());
      if (request.kind == 'RECEIPT') {
        final r = await readReceipt(request.receiptNumber ?? -1);
        final entry = await _ledger(r.entryId);
        if (entry.clientId != request.clientId ||
            entry.caseId != request.caseId ||
            r.voidedAt != null) {
          throw const OfficeFailure('الإيصال ملغى أو لا يخص هذا الحساب.');
        }
        source.add(r.toJson());
        final saved = jsonDecode(r.snapshotJson) as Map<String, dynamic>;
        title =
            '${entry.kind == 'REFUND' ? 'إيصال رد مبلغ' : 'إيصال استلام مبلغ'} رقم ${r.number}';
        sections.add({
          'label': 'بيانات الإيصال',
          'text':
              'تاريخ الإصدار: ${reportDate(r.createdAt)}\nتاريخ الحركة: ${reportDate(entry.occurredAt)}\nالمبلغ: ${moneyText(entry.amountMinor)}\nطريقة الدفع: ${methodLabels[entry.paymentMethod] ?? ''}\nالبيان: ${entry.description}\nالمُصدر: ${saved['issuer']}\nتوقيع المستلم: ____________________',
        });
      } else if (request.kind == 'STATEMENT') {
        title = 'كشف حساب الموكل';
        if (request.from != null &&
            request.through != null &&
            request.from!.isAfter(request.through!)) {
          throw const OfficeFailure('راجع نطاق تاريخ الكشف.');
        }
        final entries = account.entries.where((e) => e.voidedAt == null);
        var balance = checkedSum(
          entries
              .where(
                (e) =>
                    request.from != null &&
                    e.occurredAt.isBefore(request.from!),
              )
              .map((e) => ledgerEffect(e.kind, e.amountMinor)),
        );
        final end = request.through == null
            ? null
            : DateTime(
                request.through!.year,
                request.through!.month,
                request.through!.day + 1,
              );
        sections.add({
          'label': 'الفترة والرصيد الافتتاحي',
          'text':
              '${request.from == null ? 'من البداية' : reportDate(request.from!)} - ${request.through == null ? 'حتى الآن' : reportDate(request.through!)}\nرصيد افتتاحي: ${moneyText(balance)}',
        });
        for (final e in entries.where(
          (e) =>
              (request.from == null || !e.occurredAt.isBefore(request.from!)) &&
              (end == null || e.occurredAt.isBefore(end)),
        )) {
          balance = checkedSum([balance, ledgerEffect(e.kind, e.amountMinor)]);
          sections.add({
            'label': '${reportDate(e.occurredAt)} - ${ledgerLabels[e.kind]}',
            'text':
                '${e.description}\n${moneyText(e.amountMinor)}\nالرصيد: ${moneyText(balance)}',
          });
        }
        sections.add({
          'label': 'الرصيد الختامي',
          'text': _balanceText(balance),
        });
      } else {
        sections.add({
          'label': 'الموقف المالي للقضية ${c!.caseNumber}',
          'text':
              '${_balanceText(account.caseBalance(c.id))}\nالحساب حتى ${reportDate(time)} ويخص هذه القضية فقط.',
        });
      }
      if (pending.isNotEmpty && request.kind != 'RECEIPT') {
        sections.add({
          'label': 'تنبيه محاسبي',
          'text':
              'لا يشمل هذا الحساب المعاملات القديمة التي لم تُراجع. توجد معاملات قيد المراجعة؛ الأرصدة ليست تسوية نهائية.',
        });
      }
    }
    if (sections.isEmpty) {
      throw const OfficeFailure('اختر قسمًا واحدًا على الأقل.');
    }
    final snapshot = <String, dynamic>{
      'version': 1,
      'kind': request.kind,
      'title': title,
      'officeName': brand['name'],
      'logo': brand['logo'],
      'clientName': client.name,
      'caseNumber': c?.caseNumber,
      'date': reportDate(time),
      'createdAt': time.toIso8601String(),
      'lawyerName': actor.name,
      'lawyerPhone': actor.phone ?? '',
      'sections': sections,
    };
    return PreparedReport(
      request: request,
      createdAt: time,
      sourceHash: jsonHash(source),
      snapshot: snapshot,
    );
  });

  String _balanceText(int value) => value == 0
      ? 'الحساب مسدد'
      : '${value < 0 ? 'رصيد دائن لصالح الموكل' : 'المتبقي على الموكل'}: ${moneyText(value.abs())}';

  Future<ReportBundle> finalizeReport(
    PreparedReport preview,
    Uint8List pdf, {
    required String operationKey,
  }) => _write(
    () => _db.transaction(() async {
      final current = await prepareReport(
        preview.request,
        createdAt: preview.createdAt,
      );
      if (current.hash != preview.hash ||
          current.sourceHash != preview.sourceHash ||
          current.text != preview.text) {
        throw const OfficeFailure(
          'تغيرت البيانات منذ المعاينة. أعد إنشاء المعاينة قبل الحفظ أو المشاركة.',
        );
      }
      if (pdf.length < 5 ||
          pdf.length > 20000000 ||
          utf8.decode(pdf.take(5).toList(), allowMalformed: true) != '%PDF-') {
        throw const OfficeFailure('تعذر التحقق من ملف PDF. أعد المعاينة.');
      }
      final existing = await (_db.select(
        _db.caseReports,
      )..where((t) => t.operationKey.equals(operationKey))).getSingleOrNull();
      if (existing != null) {
        if (existing.contentHash != preview.hash ||
            existing.createdBy != staff.id) {
          _deny();
        }
        return _bundle(existing.id);
      }
      final id = const Uuid().v4();
      await _db
          .into(_db.caseReports)
          .insert(
            CaseReportsCompanion.insert(
              id: id,
              operationKey: operationKey,
              clientId: preview.request.clientId,
              caseId: Value(preview.request.caseId),
              sourceKind: preview.request.kind,
              receiptNumber: Value(preview.request.receiptNumber),
              createdBy: staff.id,
              snapshotJson: preview.snapshotJson,
              textContent: preview.text,
              contentHash: preview.hash,
              includesFinance:
                  preview.request.includeFinance ||
                  preview.request.kind != 'REPORT',
              previewedAt: _access._now,
              createdAt: Value(preview.createdAt),
            ),
          );
      await _db
          .into(_db.generatedDocuments)
          .insert(
            GeneratedDocumentsCompanion.insert(
              id: const Uuid().v4(),
              reportId: id,
              format: 'PDF',
              pageNumber: 0,
              bytes: pdf,
              contentHash: reportHash(pdf),
            ),
          );
      await recordChange(
        _db,
        entityType: 'REPORT',
        entityId: id,
        action: 'FINALIZED',
        reason: 'حفظ المحتوى بعد المعاينة',
        after: {'hash': preview.hash, 'kind': preview.request.kind},
      );
      return _bundle(id);
    }),
  );

  Future<CaseReport> _report(String id) async {
    final r = await (_db.select(
      _db.caseReports,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null || !canEdit) _deny();
    if (r.caseId != null) {
      await _case(r.caseId!);
    } else {
      await _needClient(r.clientId);
    }
    if (r.includesFinance) {
      await _financeClient(r.clientId, caseId: r.caseId);
    }
    if (reportHash(utf8.encode(r.snapshotJson)) != r.contentHash ||
        snapshotText(jsonDecode(r.snapshotJson) as Map<String, dynamic>) !=
            r.textContent) {
      throw const OfficeFailure('تعذر التحقق من سلامة التقرير.');
    }
    return r;
  }

  Future<ReportBundle> _bundle(String id) async {
    final report = await _report(id);
    final artifacts =
        await (_db.select(_db.generatedDocuments)
              ..where((t) => t.reportId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.pageNumber)]))
            .get();
    for (final a in artifacts) {
      if (a.contentHash != reportHash(a.bytes)) {
        throw const OfficeFailure('تعذر التحقق من سلامة الملف.');
      }
    }
    return ReportBundle(report, artifacts);
  }

  Future<ReportBundle> readReport(String id) => _read(() => _bundle(id));

  Future<ReportBundle> addReportImages(
    String id,
    String pdfHash,
    List<Uint8List> images,
  ) => _write(
    () => _db.transaction(() async {
      final bundle = await _bundle(id);
      if (reportHash(bundle.pdf) != pdfHash ||
          images.isEmpty ||
          images.length > 200 ||
          images.fold<int>(0, (sum, i) => sum + i.length) > 80000000 ||
          images.any(
            (i) =>
                i.length < 8 ||
                i[0] != 137 ||
                i[1] != 80 ||
                i[2] != 78 ||
                i[3] != 71,
          )) {
        throw const OfficeFailure('تعذر التحقق من صور التقرير.');
      }
      if (bundle.images.isNotEmpty) return bundle;
      for (var i = 0; i < images.length; i++) {
        await _db
            .into(_db.generatedDocuments)
            .insert(
              GeneratedDocumentsCompanion.insert(
                id: const Uuid().v4(),
                reportId: id,
                format: 'PNG',
                pageNumber: i + 1,
                bytes: images[i],
                contentHash: reportHash(images[i]),
              ),
            );
      }
      await recordChange(
        _db,
        entityType: 'REPORT',
        entityId: id,
        action: 'IMAGES',
        reason: 'حفظ صور صفحات المعاينة',
        after: {'pages': images.length},
      );
      return _bundle(id);
    }),
  );

  Future<List<CaseReport>> reportHistory({
    required String clientId,
    String? caseId,
  }) => _read(() async {
    final profile = await clientProfile(clientId);
    final ids = profile.cases.map((c) => c.id).toList();
    if (caseId != null && !ids.contains(caseId)) _deny();
    return (_db.select(_db.caseReports)
          ..where(
            (t) =>
                t.clientId.equals(clientId) &
                (caseId != null
                    ? t.caseId.equals(caseId)
                    : profile.fullAccess
                    ? const Constant(true)
                    : t.caseId.isIn(ids)) &
                ((profile.fullAccess && canReadFinance)
                    ? const Constant(true)
                    : t.includesFinance.not()),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  });
  Future<List<ShareAttempt>> shareHistory(String id) => _read(() async {
    await _report(id);
    return (_db.select(_db.shareAttempts)
          ..where((t) => t.reportId.equals(id))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  });

  Future<String> reportRecipient(String id) => _read(() async {
    final r = await _report(id);
    final full = await _fullClient(r.clientId);
    return full?.whatsappNumber ?? full?.phone ?? '';
  });

  Future<String> beginShare(
    String id, {
    required String expectedHash,
    required String recipient,
    required String channel,
    required String format,
    required bool reviewed,
  }) => _write(
    () => _db.transaction(() async {
      final bundle = await _bundle(id);
      final r = bundle.report;
      if (!reviewed ||
          r.contentHash != expectedHash ||
          !['TEXT', 'PDF', 'PNG'].contains(format) ||
          ![
            'NATIVE',
            'WHATSAPP',
            'WHATSAPP_WEB',
            'SAVE',
            'COPY',
            'PRINT',
          ].contains(channel) ||
          (format == 'PNG' && bundle.images.isEmpty)) {
        _deny();
      }
      final full = await _fullClient(r.clientId);
      if (recipient != (full?.whatsappNumber ?? full?.phone ?? '')) {
        throw const OfficeFailure(
          'تغير رقم التواصل. أعد المعاينة وراجع المستلم.',
        );
      }
      if (channel.startsWith('WHATSAPP')) {
        if (full?.whatsappConsentStatus != 'GRANTED') {
          throw const OfficeFailure(
            'لم تُسجل موافقة الموكل على التواصل عبر واتساب.',
          );
        }
        normalizedRecipient(recipient);
        if (format != 'TEXT') {
          throw const OfficeFailure(
            'واتساب مباشر يفتح نصًا فقط؛ أرفق الملفات يدويًا.',
          );
        }
      }
      if (r.sourceKind == 'RECEIPT' &&
          (await readReceipt(r.receiptNumber!)).voidedAt != null) {
        throw const OfficeFailure(
          'هذا الإيصال أُلغي؛ لا يمكن مشاركته كإيصال سارٍ.',
        );
      }
      final attempt = const Uuid().v4();
      await _db
          .into(_db.shareAttempts)
          .insert(
            ShareAttemptsCompanion.insert(
              id: attempt,
              reportId: id,
              actorId: staff.id,
              channel: channel,
              format: format,
              recipientSnapshot: recipient,
              contentHash: r.contentHash,
              status: 'STARTED',
              artifactHashesJson: jsonEncode(
                bundle.artifacts
                    .where((a) => a.format == format)
                    .map((a) => a.contentHash)
                    .toList(),
              ),
            ),
          );
      await recordChange(
        _db,
        entityType: 'SHARE',
        entityId: attempt,
        action: 'STARTED',
        reason: 'اختيار المستخدم بعد مراجعة المحتوى والمستلم',
        after: {'reportId': id, 'channel': channel, 'format': format},
      );
      return attempt;
    }),
  );

  Future<void> finishShare(
    String id,
    String status, {
    String? target,
    String? errorCode,
  }) => _write(
    () => _db.transaction(() async {
      if (!shareStatusLabels.containsKey(status) || status == 'STARTED') {
        _deny();
      }
      final a = await (_db.select(
        _db.shareAttempts,
      )..where((t) => t.id.equals(id))).getSingle();
      await _report(a.reportId);
      if (a.actorId != staff.id || a.status != 'STARTED') _deny();
      await (_db.update(
        _db.shareAttempts,
      )..where((t) => t.id.equals(id))).write(
        ShareAttemptsCompanion(
          status: Value(status),
          actualTarget: Value(target),
          errorCode: Value(errorCode),
          updatedAt: Value(_access._now),
          revision: Value(a.revision + 1),
        ),
      );
      await recordChange(
        _db,
        entityType: 'SHARE',
        entityId: id,
        action: status,
        reason: 'نتيجة العملية؛ ليست إثبات تسليم',
        after: {'status': status},
      );
    }),
  );

  Future<void> recheckShare(String id) => _read(() async {
    final a = await (_db.select(
      _db.shareAttempts,
    )..where((t) => t.id.equals(id))).getSingle();
    final bundle = await _bundle(a.reportId);
    if (a.actorId != staff.id ||
        a.status != 'STARTED' ||
        a.contentHash != bundle.report.contentHash) {
      _deny();
    }
    final client = await _fullClient(bundle.report.clientId);
    if (a.recipientSnapshot != (client?.whatsappNumber ?? client?.phone ?? '')) {
      throw const OfficeFailure('تغير المستلم؛ أعد المعاينة.');
    }
    if (a.channel.startsWith('WHATSAPP') &&
        client?.whatsappConsentStatus != 'GRANTED') {
      throw const OfficeFailure('موافقة واتساب غير متاحة الآن.');
    }
    if (bundle.report.sourceKind == 'RECEIPT' &&
        (await readReceipt(bundle.report.receiptNumber!)).voidedAt != null) {
      throw const OfficeFailure('أُلغي الإيصال قبل المشاركة.');
    }
  });

  Future<void> confirmReportSent(String id) => _write(
    () => _db.transaction(() async {
      final a = await (_db.select(
        _db.shareAttempts,
      )..where((t) => t.id.equals(id))).getSingle();
      await _report(a.reportId);
      if (a.actorId != staff.id ||
          !['OPENED', 'UNAVAILABLE'].contains(a.status) ||
          a.userConfirmedSentAt != null) {
        _deny();
      }
      await (_db.update(
        _db.shareAttempts,
      )..where((t) => t.id.equals(id))).write(
        ShareAttemptsCompanion(
          userConfirmedSentAt: Value(_access._now),
          updatedAt: Value(_access._now),
          revision: Value(a.revision + 1),
        ),
      );
      await recordChange(
        _db,
        entityType: 'SHARE',
        entityId: id,
        action: 'USER_CONFIRMED',
        reason: 'أكد المستخدم الإرسال؛ الوصول والقراءة غير مؤكدين',
      );
    }),
  );
}
