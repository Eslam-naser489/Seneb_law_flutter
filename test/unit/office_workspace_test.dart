import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/security/pin_hasher.dart';
import 'package:seneb_law/features/clients/domain/client_profile.dart';
import 'package:seneb_law/features/lawyers/domain/office_models.dart';
import 'package:seneb_law/features/search/data/arabic_search.dart';
import 'package:seneb_law/features/search/domain/search_models.dart';

void main() {
  late AppDatabase db;
  late AppRepository baseline;
  late OfficeAccess access;
  late DateTime now;
  const ownerPin = '481637';
  const tempPin = '671293';
  const staffPin = '906245';
  late String ownerId;

  Future<ScopedAppRepository> unlock(String id, String pin) async {
    await access.signIn(id, pin);
    return access.workspace(access.session!);
  }

  Future<ScopedAppRepository> owner() => unlock(ownerId, ownerPin);

  Future<ScopedAppRepository> staff(String id) async {
    await access.signIn(id, tempPin);
    final temporary = access.session!;
    expect(temporary.mustChangePin, isTrue);
    expect(() => access.workspace(temporary), throwsA(isA<OfficeFailure>()));
    await access.changeTemporaryPin(temporary, staffPin);
    expect(access.session, isNull);
    return unlock(id, staffPin);
  }

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: registerSearchFunctions),
    );
    baseline = AppRepository(db);
    now = DateTime.utc(2026, 11, 11, 12);
    access = OfficeAccess(baseline, clock: () => now);
  });

  tearDown(() async {
    access.dispose();
    await db.close();
  });

  Future<void> bootstrap() async {
    await access.bootstrapOwner('مالك تجريبي', ownerPin);
    ownerId = (await access.unlockProfiles()).single.id;
  }

  test(
    'initial owner preserves the old profile, PIN reset needs reauthentication and lockouts persist',
    () async {
      final existing = await baseline.addLawyer('مالك سابق');
      final oldClient = await baseline.addClient(
        name: 'موكل سابق',
        lawyerId: existing,
      );
      await access.bootstrapOwner('', ownerPin, legacyId: existing);
      ownerId = existing;
      final workspace = await owner();
      expect(
        (await workspace.clientProfile(oldClient)).assignments.single.lawyerId,
        existing,
      );
      await expectLater(
        access.bootstrapOwner('آخر', tempPin),
        throwsA(isA<OfficeFailure>()),
      );
      final id = await workspace.saveStaff(
        const StaffInput(name: 'عضو تجريبي', role: OfficeRole.lawyer),
        initialPin: tempPin,
      );
      final second = await workspace.saveStaff(
        const StaffInput(name: 'عضو ثانٍ', role: OfficeRole.trainee),
        initialPin: tempPin,
      );
      final creds = await db.select(db.localCredentials).get();
      expect(creds.map((c) => c.pinVerifier).toSet(), hasLength(3));
      expect(creds.every((c) => c.algorithm == PinHasher.algorithm), isTrue);
      await expectLater(
        workspace.resetStaffPin(id, '111111', staffPin, 'إعادة تعيين تجريبية'),
        throwsA(isA<OfficeFailure>()),
      );
      await workspace.resetStaffPin(
        id,
        ownerPin,
        tempPin,
        'إعادة تعيين تجريبية',
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          access.signIn(id, 'invalid'),
          throwsA(isA<OfficeFailure>()),
        );
      }
      final locked = await (db.select(
        db.localCredentials,
      )..where((t) => t.lawyerId.equals(id))).getSingle();
      expect(locked.failedAttempts, 5);
      await expectLater(
        access.signIn(id, tempPin),
        throwsA(isA<OfficeFailure>()),
      );
      now = now.add(const Duration(seconds: 31));
      final staffWorkspace = await staff(id);
      expect(staffWorkspace.staff.id, id);
      await expectLater(workspace.team(), throwsA(isA<OfficeFailure>()));
      final currentOwner = await owner();
      await currentOwner.setStaffActive(second, false, 'اختبار إيقاف');
      await expectLater(
        access.signIn(second, tempPin),
        throwsA(isA<OfficeFailure>()),
      );
      final audit = await db.select(db.auditLog).get();
      expect(
        audit.singleWhere((a) => a.action == 'PIN_RESET').actorId,
        existing,
      );
      expect(audit.where((a) => a.action == 'PIN_CHANGED').single.actorId, id);
      final auditText = audit.map((a) => a.toJson().toString()).join();
      for (final secret in [ownerPin, tempPin, staffPin]) {
        expect(auditText.contains(secret), isFalse);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a case-only lawyer sees one case, no private client data, and no unrelated records',
    () async {
      await bootstrap();
      final management = await owner();
      final lawyer = await management.saveStaff(
        const StaffInput(name: 'محامي الاختبار', role: OfficeRole.lawyer),
        initialPin: tempPin,
      );
      final client = await management.addClient(name: 'هُدَى منصور');
      final other = await management.addClient(name: 'موكل مستقل');
      await management.saveClientProfile(
        client,
        const ClientEdit('هُدَى منصور', {
          'nationalId': '٢٩٠١١١١٠١٠١٠١٠',
          'phone': '+20 (100) 123 4567',
          'notes': 'سري خاص بالموكل',
        }, consent: 'UNKNOWN'),
      );
      final granted = await management.addCase(
        clientId: client,
        caseNumber: '١١١/٢٠٢٦',
        opponentName: 'إيمان',
      );
      final denied = await management.addCase(
        clientId: client,
        caseNumber: '٢٢٢/٢٠٢٦',
        opponentName: 'طرف محجوب',
      );
      await management.addCaseNote(
        caseId: granted,
        content: 'مُذَكِّرَة  العَرْض',
      );
      await management.addCaseNote(caseId: denied, content: 'البيان المخفي');
      await management.assign(
        granted,
        lawyer,
        forCase: true,
        role: 'LEAD',
        reason: 'اختبار إسناد قضية',
      );
      await db.customStatement('DROP TRIGGER legacy_insert');
      for (final entry in [
        (id: 'valid', clientId: client),
        (id: 'mismatch', clientId: other),
      ]) {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: entry.id,
                title: 'حركة قديمة',
                amount: 10,
                type: 'INCOME',
                caseId: Value(granted),
                clientId: Value(entry.clientId),
              ),
            );
      }
      final scoped = await staff(lawyer);
      final rows = await scoped.getCasesWithClients();
      expect(rows.map((c) => c.caseEntity.id), [granted]);
      expect(rows.single.client.nationalId, isNull);
      final profile = await scoped.clientProfile(client);
      expect(profile.fullAccess, isFalse);
      expect(profile.client.phone, isNull);
      expect(profile.history, isNull);
      expect(profile.notes.single.caseId, granted);
      expect((await scoped.getCaseTransactions(granted)).map((t) => t.id), [
        'valid',
      ]);
      await expectLater(
        scoped.getCaseTransactions(denied),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.getAllTransactions(),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.restoreBackupIsolated(
          Directory('synthetic-backup'),
          Directory('synthetic-output'),
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.caseDetails(denied),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.getCaseDocuments(denied),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.resolveDocumentPath('documents/unknown.pdf'),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.addCaseNote(caseId: denied, content: 'لا يحفظ'),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.updateCaseStatus(denied, 'CLOSED', reason: 'لا يسمح'),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        scoped.assign(
          granted,
          lawyer,
          forCase: true,
          role: 'ASSISTANT',
          reason: 'لا يسمح',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect(
        await scoped.search('البيان المخفي', const SearchFilter()),
        isEmpty,
      );
      expect(
        await scoped.search('29011110101010', const SearchFilter()),
        isEmpty,
      );
      expect(await scoped.search('سري خاص', const SearchFilter()), isEmpty);
      expect(
        (await scoped.search(
          'مذكره   العرض',
          const SearchFilter(),
        )).single.caseId,
        granted,
      );
      expect(
        (await scoped.search('هدي منصور', const SearchFilter())).single.caseId,
        granted,
      );
      final inFlight = scoped.clientProfile(client);
      final invalidated = expectLater(inFlight, throwsA(isA<OfficeFailure>()));
      access.lock();
      await invalidated;
      await expectLater(
        scoped.getCasesWithClients(),
        throwsA(isA<OfficeFailure>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'client profile consent, search filters, assignment replacement and archive restoration',
    () async {
      await bootstrap();
      final workspace = await owner();
      final lawyer = await workspace.saveStaff(
        const StaffInput(name: 'محامٍ أول', role: OfficeRole.lawyer),
        initialPin: tempPin,
      );
      final other = await workspace.saveStaff(
        const StaffInput(name: 'محامٍ ثانٍ', role: OfficeRole.partner),
        initialPin: tempPin,
      );
      final client = await workspace.addClient(
        name: 'أمِينة  الهُدى',
        lawyerId: lawyer,
      );
      const fields = {
        'phone': '+20 (100) 123 4567',
        'phoneSecondary': '٠١١ ٥٥٥ ١٢٣٤٥',
        'nationalId': '٢٩٠١١١١٠١٠١٠١٠',
        'whatsappNumber': '01001234567',
        'address': 'القاهرة',
        'email': 'synthetic@example.test',
        'notes': 'المستند الأصلي',
        'occupation': 'محاسب',
        'referralSource': 'زيارة',
      };
      await expectLater(
        workspace.saveClientProfile(
          client,
          const ClientEdit('أمِينة الهُدى', fields, consent: 'GRANTED'),
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await workspace.saveClientProfile(
        client,
        const ClientEdit(
          'أمِينة الهُدى',
          fields,
          consent: 'GRANTED',
          consentSource: 'موافقة مكتوبة',
        ),
      );
      final record = await workspace.clientProfile(client);
      expect(record.client.consentRecordedBy, ownerId);
      expect(record.client.consentSource, 'موافقة مكتوبة');
      expect(record.client.consentRecordedAt!.toUtc(), now);
      expect(record.client.address, 'القاهرة');
      expect(record.client.phoneSecondary, fields['phoneSecondary']);
      final caseId = await workspace.addCase(
        clientId: client,
        caseNumber: '١٢٠/۲۰۲۶',
        opponentName: 'إبراهيم',
      );
      await workspace.addSession(
        caseId: caseId,
        sessionDate: DateTime.now().add(const Duration(days: 2)),
        courtLocation: 'محكمة',
      );
      await workspace.addCaseNote(caseId: caseId, content: 'مُذَكِّرة الختام');
      await workspace.assign(
        caseId,
        lawyer,
        forCase: true,
        role: 'LEAD',
        reason: 'الإسناد الأول',
      );
      await expectLater(
        workspace.assign(
          caseId,
          other,
          forCase: true,
          role: 'LEAD',
          reason: 'استبدال',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect(
        (await workspace.assignments(caseId, forCase: true)).single.lawyerId,
        lawyer,
      );
      await workspace.assign(
        caseId,
        other,
        forCase: true,
        role: 'LEAD',
        reason: 'تغيير المسؤول',
        replaceLead: true,
      );
      final history = await workspace.assignments(caseId, forCase: true);
      expect(history.where((a) => a.endedAt == null).single.lawyerId, other);
      expect(history.where((a) => a.endedAt != null).single.lawyerId, lawyer);
      expect((await workspace.workload(lawyer)).activeCases, 1);
      expect((await workspace.workload(other)).upcomingSessions, 1);
      await workspace.assign(
        caseId,
        ownerId,
        forCase: true,
        role: 'ASSISTANT',
        reason: 'متابعة المالك',
      );
      expect((await workspace.myCases()).single.caseEntity.id, caseId);

      for (final text in [
        'امينه   الهدي',
        '01001234567',
        '01155512345',
        '۲۹۰۱۱۱۱۰۱۰۱۰۱۰',
        'المستند الاصلي',
      ]) {
        expect(
          (await workspace.search(text, const SearchFilter())).single.clientId,
          client,
          reason: text,
        );
      }
      for (final text in ['120/2026', 'ابراهيم', 'مذكره الختام']) {
        expect(
          (await workspace.search(
            text,
            SearchFilter(lawyerId: other, status: 'ACTIVE'),
          )).single.caseId,
          caseId,
        );
      }
      expect(
        await workspace.search(
          'ابراهيم',
          SearchFilter(lawyerId: other, status: 'CLOSED'),
        ),
        isEmpty,
      );
      expect(
        await workspace.search("not%'_matching", const SearchFilter()),
        isEmpty,
      );
      await workspace.setArchived(client, true);
      expect(await workspace.search('امينه', const SearchFilter()), isEmpty);
      expect(
        (await workspace.search(
          'امينه',
          const SearchFilter(archive: ArchiveFilter.archived),
        )).single.archived,
        isTrue,
      );
      await workspace.setArchived(client, false);
      expect((await workspace.getActiveClients()).single.id, client);
      final audit = await db.select(db.auditLog).get();
      expect(
        audit
            .where((e) => e.entityType == 'CASE_ASSIGNMENT')
            .every((e) => e.actorId == ownerId),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'trainee can view assigned case sessions and notes while financial and write calls are denied',
    () async {
      await bootstrap();
      final management = await owner();
      final id = await management.saveStaff(
        const StaffInput(name: 'متدرب', role: OfficeRole.trainee),
        initialPin: tempPin,
      );
      final client = await management.addClient(
        name: 'موكل تجريبي',
        lawyerId: id,
      );
      final caseId = await management.addCase(
        clientId: client,
        caseNumber: '303',
      );
      await management.addCaseNote(caseId: caseId, content: 'ملاحظة متاحة');
      final trainee = await staff(id);
      expect(
        (await trainee.getCaseNotes(caseId)).single.content,
        'ملاحظة متاحة',
      );
      expect((await trainee.clientProfile(client)).history, isNull);
      await expectLater(
        trainee.getCaseTransactions(caseId),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        trainee.addClient(name: 'غير مسموح'),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        trainee.addCaseNote(caseId: caseId, content: 'غير مسموح'),
        throwsA(isA<OfficeFailure>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
