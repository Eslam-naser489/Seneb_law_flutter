part of 'app_repository.dart';

class StaffSession {
  StaffSession._(
    this.person,
    this._credentialVersion, {
    required this.mustChangePin,
  });
  final OfficeLawyerEntity person;
  final int _credentialVersion;
  final bool mustChangePin;
  OfficeRole get role => OfficeRole.parse(person.role);
}

class OfficeAccess extends ChangeNotifier {
  OfficeAccess(
    this._base, {
    DateTime Function()? clock,
    this.hasher = const PinHasher(),
  }) : _clock = clock ?? DateTime.now;

  final AppRepository _base;
  final DateTime Function() _clock;
  final PinHasher hasher;
  StaffSession? _session;
  int _generation = 0;
  bool _disposed = false;
  AppDatabase get _db => _base._db;
  StaffSession? get session => _session;
  DateTime get _now => _clock().toUtc();

  void lock() {
    _generation++;
    final wasUnlocked = _session != null;
    _session = null;
    if (wasUnlocked && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    lock();
    super.dispose();
  }

  Future<bool> needsOwnerSetup() async {
    final row = await (_db.select(
      _db.officeLawyers,
    )..where((t) => t.role.equals(OfficeRole.owner.code))).getSingleOrNull();
    return row == null;
  }

  Future<List<UnlockProfile>> unlockProfiles() async =>
      (await _profiles(activeOnly: true))
          .map(
            (profile) => UnlockProfile(
              profile.person.id,
              profile.person.name,
              profile.hasPin,
            ),
          )
          .toList();
  Future<List<StaffProfile>> _profiles({required bool activeOnly}) async {
    final staff = _db.officeLawyers;
    final creds = _db.localCredentials;
    final query = _db.select(staff).join([
      leftOuterJoin(
        creds,
        creds.lawyerId.equalsExp(staff.id),
        useColumns: false,
      ),
    ]);
    query.addColumns([creds.id, creds.mustChangePin]);
    query.where(
      staff.deletedAt.isNull() &
          (activeOnly ? staff.isActive : const Constant(true)),
    );
    query.orderBy([OrderingTerm.asc(staff.name)]);
    final photos = <String, List<int>>{};
    if (!activeOnly) {
      final settings =
          await (_db.select(_db.appSettings)..where(
                (t) => t.key.equals('staff_photo') & t.deletedAt.isNull(),
              ))
              .get();
      for (final setting in settings) {
        final owner = setting.scopeOwnerId;
        if (owner != null && setting.valueJson.length <= 700000) {
          try {
            final encoded = jsonDecode(setting.valueJson);
            if (encoded is String) photos[owner] = base64Decode(encoded);
          } on FormatException {
            continue;
          }
        }
      }
    }
    return (await query.get())
        .map(
          (row) => StaffProfile(
            row.readTable(staff),
            hasPin: row.read(creds.id) != null,
            mustChangePin: row.read(creds.mustChangePin) ?? false,
            photo: photos[row.readTable(staff).id],
          ),
        )
        .toList();
  }

  Future<void> bootstrapOwner(String name, String pin, {String? legacyId}) =>
      _base._writes.run(() async {
        if (!await needsOwnerSetup()) {
          throw const OfficeFailure('تم إعداد مالك المكتب بالفعل.');
        }
        final hash = await hasher.hash(pin);
        await _db.transaction(() async {
          if (!await needsOwnerSetup()) {
            throw const OfficeFailure('تم إعداد مالك المكتب بالفعل.');
          }
          final String id;
          if (legacyId != null) {
            final row = await _person(legacyId);
            if (!row.isActive) throw const OfficeFailure('المستخدم غير نشط.');
            id = row.id;
            await (_db.update(
              _db.officeLawyers,
            )..where((t) => t.id.equals(id))).write(
              OfficeLawyersCompanion(
                role: Value(OfficeRole.owner.code),
                updatedAt: Value(_now),
                revision: Value(row.revision + 1),
              ),
            );
          } else {
            id = const Uuid().v4();
            await _db
                .into(_db.officeLawyers)
                .insert(
                  OfficeLawyersCompanion.insert(
                    id: id,
                    name: _name(name),
                    role: Value(OfficeRole.owner.code),
                  ),
                );
          }
          await _storePin(id, hash, mustChange: false);
          await recordChange(
            _db,
            actorId: id,
            entityType: 'STAFF',
            entityId: id,
            action: 'OWNER_SETUP',
            reason: 'إعداد مالك المكتب',
          );
        });
      });

  Future<void> signIn(String id, String pin) {
    lock();
    final generation = _generation;
    return _base._writes.run(() async {
      if (generation != _generation) {
        throw const OfficeFailure('انتهت محاولة فتح البرنامج.');
      }
      final result = await _checkPin(id, pin);
      if (_disposed || generation != _generation) {
        throw const OfficeFailure('انتهت محاولة فتح البرنامج.');
      }
      _session = StaffSession._(
        result.$1,
        result.$2.credentialsVersion,
        mustChangePin: result.$2.mustChangePin,
      );
      notifyListeners();
    });
  }

  Future<void> changeTemporaryPin(StaffSession session, String pin) =>
      _base._writes.run(() async {
        await _validate(session, allowTemporary: true);
        if (!session.mustChangePin) {
          throw const OfficeFailure('لا يلزم تغيير الرقم السري.');
        }
        final credential = await _credential(session.person.id);
        if (await hasher.verify(pin, credential.pinVerifier)) {
          throw const OfficeFailure('اختر رقمًا مختلفًا عن الرقم المؤقت.');
        }
        final hash = await hasher.hash(pin);
        await _validate(session, allowTemporary: true);
        await _db.transaction(() async {
          await _storePin(session.person.id, hash, mustChange: false);
          await recordChange(
            _db,
            actorId: session.person.id,
            entityType: 'STAFF',
            entityId: session.person.id,
            action: 'PIN_CHANGED',
            reason: 'تغيير الرقم المؤقت',
          );
        });
        lock();
      });

  ScopedAppRepository workspace(StaffSession session) {
    _assertCurrent(session);
    if (session.mustChangePin) {
      throw const OfficeFailure('غيّر الرقم السري المؤقت أولًا.');
    }
    return ScopedAppRepository._(this, session);
  }

  void _assertCurrent(StaffSession session) {
    if (!identical(_session, session)) {
      throw const OfficeFailure('الجلسة مقفلة. افتح البرنامج مجددًا.');
    }
  }

  Future<void> _validate(
    StaffSession session, {
    bool allowTemporary = false,
  }) async {
    _assertCurrent(session);
    final person = await _person(session.person.id);
    final creds = await _credential(person.id);
    _assertCurrent(session);
    if (!person.isActive ||
        person.role != session.person.role ||
        creds.credentialsVersion != session._credentialVersion) {
      lock();
      throw const OfficeFailure('تغيّر الحساب. افتح البرنامج مجددًا.');
    }
    if (creds.mustChangePin && !allowTemporary) {
      throw const OfficeFailure('غيّر الرقم السري المؤقت أولًا.');
    }
  }

  Future<OfficeLawyerEntity> _person(String id) async {
    final row = await (_db.select(
      _db.officeLawyers,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) throw const OfficeFailure('هذا المستخدم غير متاح.');
    return row;
  }

  Future<LocalCredential> _credential(String id) async {
    final row = await (_db.select(
      _db.localCredentials,
    )..where((t) => t.lawyerId.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const OfficeFailure('لم يُضبط رقم سري لهذا المستخدم.');
    }
    return row;
  }

  Future<(OfficeLawyerEntity, LocalCredential)> _checkPin(
    String id,
    String pin,
  ) async {
    final person = await _person(id);
    if (!person.isActive) throw const OfficeFailure('هذا المستخدم غير نشط.');
    final row = await _credential(id);
    if (row.lockedUntil != null && row.lockedUntil!.isAfter(_now)) {
      final seconds = row.lockedUntil!.difference(_now).inSeconds + 1;
      throw OfficeFailure('محاولات متكررة. حاول بعد $seconds ثانية.');
    }
    final ok =
        row.algorithm == PinHasher.algorithm &&
        row.parametersJson == PinHasher.parameters &&
        await hasher.verify(pin, row.pinVerifier);
    final attempts = ok ? 0 : row.failedAttempts + 1;
    final cooldown = attempts < 5
        ? null
        : _now.add(Duration(seconds: 30 * (1 << (attempts - 5).clamp(0, 5))));
    await (_db.update(
      _db.localCredentials,
    )..where((t) => t.id.equals(row.id))).write(
      LocalCredentialsCompanion(
        failedAttempts: Value(attempts),
        lockedUntil: Value(cooldown),
        updatedAt: Value(_now),
      ),
    );
    if (!ok) throw const OfficeFailure('الرقم السري غير صحيح.');
    return (person, row);
  }

  Future<void> _storePin(
    String id,
    String hash, {
    required bool mustChange,
  }) async {
    final previous = await (_db.select(
      _db.localCredentials,
    )..where((t) => t.lawyerId.equals(id))).getSingleOrNull();
    await _db
        .into(_db.localCredentials)
        .insertOnConflictUpdate(
          LocalCredentialsCompanion.insert(
            id: previous?.id ?? const Uuid().v4(),
            lawyerId: id,
            pinVerifier: hash,
            algorithm: PinHasher.algorithm,
            parametersJson: PinHasher.parameters,
            failedAttempts: const Value(0),
            lockedUntil: const Value(null),
            mustChangePin: Value(mustChange),
            credentialsVersion: Value((previous?.credentialsVersion ?? 0) + 1),
            createdAt: previous == null
                ? const Value.absent()
                : Value(previous.createdAt),
            updatedAt: Value(_now),
          ),
        );
  }

  static String _name(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > 150) {
      throw const OfficeFailure('أدخل اسمًا صالحًا.');
    }
    return text;
  }
}
