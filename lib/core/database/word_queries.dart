part of 'app_repository.dart';

extension WordWorkspace on ScopedAppRepository {
  Future<List<WordTemplate>> wordTemplates() => _read(() async {
    if (!canEdit) _deny();
    return (_db.select(_db.wordTemplates)..orderBy([
          (t) => OrderingTerm.asc(t.name),
          (t) => OrderingTerm.desc(t.version),
        ]))
        .get();
  });

  Future<WordTemplate> _wordTemplate(String id) async {
    if (!canEdit) _deny();
    final t = await (_db.select(
      _db.wordTemplates,
    )..where((t) => t.id.equals(id))).getSingle();
    if (reportHash(t.bytes) != t.checksum) {
      throw const TemplateFailure('تلف القالب المحفوظ؛ استعد نسخة سليمة.');
    }
    return t;
  }

  Future<String> importWordTemplate(
    String name,
    String category,
    Uint8List bytes,
  ) => _write(() async {
    name = name.trim();
    category = category.trim();
    if (name.isEmpty ||
        category.isEmpty ||
        name.length > 120 ||
        category.length > 80) {
      throw const TemplateFailure('أدخل اسم القالب وتصنيفه ضمن حدود الطول.');
    }
    final fields = DocxEngine.inspect(bytes).toList()..sort();
    final checksum = reportHash(bytes);
    return _db.transaction(() async {
      final old =
          await (_db.select(_db.wordTemplates)
                ..where((t) => t.name.equals(name))
                ..orderBy([(t) => OrderingTerm.desc(t.version)]))
              .get();
      if (old.isNotEmpty &&
          old.first.checksum == checksum &&
          old.first.category == category) {
        return old.first.id;
      }
      final id = const Uuid().v4();
      await _db
          .into(_db.wordTemplates)
          .insert(
            WordTemplatesCompanion.insert(
              id: id,
              name: name,
              category: category,
              version: old.isEmpty ? 1 : old.first.version + 1,
              bytes: bytes,
              checksum: checksum,
              fieldsJson: jsonEncode(fields),
              createdBy: staff.id,
            ),
          );
      await recordChange(
        _db,
        entityType: 'WORD_TEMPLATE',
        entityId: id,
        action: 'IMPORT',
        reason: 'فحص وحفظ إصدار مستقل من القالب',
      );
      return id;
    });
  }, owner: true);

  Future<WordContext> wordContext(
    String templateId,
    String clientId, {
    String? caseId,
  }) => _read(() async {
    final template = await _wordTemplate(templateId);
    final client = await _fullClient(clientId);
    if (client == null) _deny();
    if (client.isArchived) {
      throw const TemplateFailure('استعد الموكل المؤرشف قبل إنشاء مستند.');
    }
    final c = caseId == null ? null : await _case(caseId);
    if (c != null && c.clientId != clientId) _deny();
    final defaults = <String, String>{
      'client_name': client.name,
      'client_national_id': client.nationalId ?? '',
      'client_phone': client.phone ?? '',
      'client_address': client.address ?? '',
      'case_number': c?.caseNumber ?? '',
      'opponent_name': c?.opponentName ?? '',
      'lawyer_name': staff.name,
    };
    return WordContext(template, {
      for (final key
          in (jsonDecode(template.fieldsJson) as List).cast<String>())
        key: defaults[key] ?? '',
    });
  });

  Future<WordDraft> prepareWord(
    String templateId,
    String clientId, {
    String? caseId,
    required Map<String, String> values,
    required bool sensitiveReviewed,
  }) => _read(() async {
    final ctx = await wordContext(templateId, clientId, caseId: caseId);
    if (ctx.values.containsKey('client_national_id') && !sensitiveReviewed) {
      throw const TemplateFailure(
        'راجع الرقم القومي ووافق على إدراجه في المستند.',
      );
    }
    if (values.keys.toSet().difference(ctx.values.keys.toSet()).isNotEmpty) {
      throw const TemplateFailure('حقول إضافية غير معروفة.');
    }
    final input = {for (final key in ctx.values.keys) key: values[key] ?? ''};
    DocxEngine.generate(ctx.template.bytes, input);
    final client = (await _fullClient(clientId))!;
    final c = caseId == null ? null : await _case(caseId);
    final source = reportHash(
      utf8.encode(
        jsonEncode([
          ctx.template.checksum,
          client.revision,
          c?.revision,
          ctx.values,
          staff.id,
        ]),
      ),
    );
    return WordDraft(
      templateId: templateId,
      clientId: clientId,
      caseId: caseId,
      values: input,
      sourceHash: source,
    );
  });

  Future<WordDocument> finalizeWord(
    WordDraft draft, {
    required String operationKey,
    required bool reviewed,
  }) => _write(() async {
    if (!reviewed || operationKey.trim().isEmpty) {
      throw const TemplateFailure('راجع البيانات قبل الحفظ.');
    }
    await _needClient(draft.clientId);
    final prior = await (_db.select(
      _db.wordDocuments,
    )..where((t) => t.operationKey.equals(operationKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.createdBy != staff.id ||
          prior.inputJson != draft.inputJson ||
          prior.templateId != draft.templateId ||
          prior.clientId != draft.clientId ||
          prior.caseId != draft.caseId ||
          prior.sourceHash != draft.sourceHash) {
        throw const TemplateFailure('مفتاح العملية مستخدم لمستند آخر.');
      }
      return _wordDocument(prior.id);
    }
    final fresh = await prepareWord(
      draft.templateId,
      draft.clientId,
      caseId: draft.caseId,
      values: draft.values,
      sensitiveReviewed: reviewed,
    );
    if (fresh.sourceHash != draft.sourceHash) {
      throw const TemplateFailure('تغيرت بيانات المصدر؛ أعد مراجعة البيانات.');
    }
    final template = await _wordTemplate(draft.templateId);
    final bytes = DocxEngine.generate(template.bytes, draft.values);
    return _db.transaction(() async {
      final id = const Uuid().v4();
      await _db
          .into(_db.wordDocuments)
          .insert(
            WordDocumentsCompanion.insert(
              id: id,
              operationKey: operationKey,
              templateId: template.id,
              clientId: draft.clientId,
              caseId: Value(draft.caseId),
              title: template.name,
              inputJson: draft.inputJson,
              sourceHash: draft.sourceHash,
              bytes: bytes,
              checksum: reportHash(bytes),
              createdBy: staff.id,
            ),
          );
      await recordChange(
        _db,
        entityType: 'WORD_DOCUMENT',
        entityId: id,
        action: 'GENERATE',
        reason: 'إنشاء مستند من بيانات مراجعة دون تغيير بيانات المصدر',
      );
      return _wordDocument(id);
    });
  });

  Future<WordDocument> _wordDocument(String id) async {
    if (!canEdit) _deny();
    final doc = await (_db.select(
      _db.wordDocuments,
    )..where((t) => t.id.equals(id))).getSingle();
    await _needClient(doc.clientId);
    if (doc.caseId != null) await _case(doc.caseId!);
    if (reportHash(doc.bytes) != doc.checksum) {
      throw const TemplateFailure('تلف الملف؛ استعد نسخة سليمة.');
    }
    return doc;
  }

  Future<WordDocument> readWordDocument(String id) =>
      _read(() => _wordDocument(id));
  Future<List<WordDocument>> wordDocuments(String clientId, {String? caseId}) =>
      _read(() async {
        if (!canEdit) _deny();
        await _needClient(clientId);
        if (caseId != null && (await _case(caseId)).clientId != clientId) {
          _deny();
        }
        return (_db.select(_db.wordDocuments)
              ..where(
                (t) =>
                    t.clientId.equals(clientId) &
                    (caseId == null
                        ? const Constant(true)
                        : t.caseId.equals(caseId)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
      });
  Future<List<WordShareAttempt>> wordShareHistory(String id) => _read(() async {
    await _wordDocument(id);
    return (_db.select(_db.wordShareAttempts)
          ..where((t) => t.documentId.equals(id))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  });
  Future<String> beginWordHandoff(
    String id,
    String channel, {
    required String checksum,
    required bool reviewed,
  }) => _write(() async {
    final doc = await _wordDocument(id);
    if (!['OPEN', 'SAVE', 'NATIVE'].contains(channel) ||
        (channel == 'NATIVE' && !reviewed) ||
        checksum != doc.checksum) {
      throw const TemplateFailure('راجع المستند قبل المشاركة.');
    }
    final attempt = const Uuid().v4();
    await _db.transaction(() async {
      await _db
          .into(_db.wordShareAttempts)
          .insert(
            WordShareAttemptsCompanion.insert(
              id: attempt,
              documentId: id,
              actorId: staff.id,
              channel: channel,
              checksum: checksum,
              status: 'STARTED',
            ),
          );
      await recordChange(
        _db,
        entityType: 'WORD_SHARE',
        entityId: attempt,
        action: 'STARTED',
        reason: 'بدء إجراء خارجي مقصود بعد مراجعة المستخدم',
      );
    });
    return attempt;
  });
  Future<void> authorizeWordHandoff(String id) => _read(() async {
    final a = await (_db.select(
      _db.wordShareAttempts,
    )..where((t) => t.id.equals(id))).getSingle();
    if (a.actorId != staff.id || a.status != 'STARTED') _deny();
    final doc = await _wordDocument(a.documentId);
    if (doc.checksum != a.checksum) _deny();
  });
  Future<void> finishWordHandoff(String id, String status) => _write(() async {
    await authorizeWordHandoff(id);
    if (![
      'OPENED',
      'SAVED',
      'CANCELLED',
      'FAILED',
      'UNAVAILABLE',
    ].contains(status)) {
      _deny();
    }
    await _db.transaction(() async {
      await (_db.update(
        _db.wordShareAttempts,
      )..where((t) => t.id.equals(id))).write(
        WordShareAttemptsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await recordChange(
        _db,
        entityType: 'WORD_SHARE',
        entityId: id,
        action: status,
        reason: 'نتيجة فتح أو حفظ أو مشاركة؛ ليست إثبات تسليم',
      );
    });
  });
}
