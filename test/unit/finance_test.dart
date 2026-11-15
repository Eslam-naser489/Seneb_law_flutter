import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/finance/domain/finance_models.dart';
import 'package:seneb_law/features/finance/data/finance_pdf.dart';
import 'package:seneb_law/features/finance/data/installment_reminders.dart';
import 'package:seneb_law/features/lawyers/domain/office_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late OfficeAccess access;
  late ScopedAppRepository repo;
  late String client, caseId, ownerId;
  final date = DateTime(2026, 1, 10);
  var sequence = 0;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    access = OfficeAccess(AppRepository(db));
    await access.bootstrapOwner('مالك اصطناعي', '481637');
    ownerId = (await access.unlockProfiles()).single.id;
    await access.signIn(ownerId, '481637');
    repo = access.workspace(access.session!);
    client = await repo.addClient(name: 'موكل اختبار');
    caseId = await repo.addCase(clientId: client, caseNumber: '١٢٣/٢٠٢٦');
  });
  tearDown(() async {
    access.dispose();
    await db.close();
  });
  Future<String> post(
    String kind,
    int minor, {
    String? c,
    String? caseRef,
    String? key,
    DateTime? due,
  }) => repo.postLedger(
    LedgerInput(
      clientId: c ?? client,
      caseId: caseRef,
      kind: kind,
      amountMinor: minor,
      description: 'حركة اختبار $kind',
      occurredAt: date,
      paymentMethod: ['PAYMENT', 'REFUND', 'EXPENSE_ADVANCE'].contains(kind)
          ? 'CASH'
          : null,
      dueAt: due,
    ),
    operationKey: key ?? 'op-${sequence++}',
  );

  test(
    'advance, client costs, discounts, refunds and signed corrections balance independently of office cash',
    () async {
      await post('PAYMENT', 30000);
      expect((await repo.clientAccount(client)).balance, -30000);
      await post('FEE', 100000, caseRef: caseId);
      await post('EXPENSE_ADVANCE', 5000, caseRef: caseId);
      await post('DISCOUNT', 10000);
      await post('REFUND', 2000);
      await post('ADJUSTMENT', -3000);
      await repo.saveOfficeExpense(
        amountMinor: 20000,
        description: 'إيجار',
        category: 'إيجار',
        paymentMethod: 'BANK',
        occurredAt: date,
        reason: 'إيجار اختباري',
        operationKey: 'office',
      );
      final a = await repo.clientAccount(client),
          d = await repo.financeDashboard();
      expect(a.balance, 64000);
      expect(a.caseBalance(caseId), 105000);
      expect(d.collected, 30000);
      expect(d.officeSpent, 20000);
      expect(d.costs, 5000);
      expect(d.cashMovement, 3000);
      expect(d.monthlyNet['2026-01'], 3000);
      expect(d.collectedByLawyer[ownerId], 28000);
    },
  );

  test(
    'installments never double-charge and allocations enforce client, case, credit, charge and installment bounds',
    () async {
      await repo.createAgreement(
        caseId: caseId,
        kind: 'MILESTONE',
        amountMinor: 100000,
        terms: 'أتعاب تجريبية',
        schedule: [
          InstallmentInput('الأول', 40000, DateTime(2026, 1, 1)),
          InstallmentInput('الثاني', 60000, DateTime(2026, 2, 1)),
        ],
        operationKey: 'agreement',
      );
      var a = await repo.clientAccount(client);
      expect(a.balance, 100000);
      expect(a.entries, hasLength(1));
      final charge = a.entries.single.id,
          payment = await post('PAYMENT', 50000);
      await repo.allocatePayment(
        paymentId: payment,
        chargeId: charge,
        installmentId: a.installments.first.id,
        amountMinor: 40000,
        reason: 'سداد الأول',
        operationKey: 'allocate',
      );
      a = await repo.clientAccount(client);
      expect(a.installmentRemaining(a.installments.first), 0);
      expect(a.balance, 50000);
      expect(a.unappliedCredit, 10000);
      expect(a.caseBalance(caseId), 60000);
      await expectLater(
        repo.allocatePayment(
          paymentId: payment,
          chargeId: charge,
          installmentId: a.installments.last.id,
          amountMinor: 10001,
          reason: 'زيادة',
          operationKey: 'over',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        repo.allocatePayment(
          paymentId: payment,
          chargeId: charge,
          amountMinor: 100,
          reason: 'بلا قسط',
          operationKey: 'missing',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect((await repo.financeDashboard()).aging(DateTime(2026, 3, 15)), {
        '1–30': 0,
        '31–60': 60000,
        '61–90': 0,
        '90+': 0,
      });
      final other = await repo.addClient(name: 'موكل ثان');
      final otherCharge = await post('FEE', 10000, c: other);
      await expectLater(
        repo.allocatePayment(
          paymentId: payment,
          chargeId: otherCharge,
          amountMinor: 1,
          reason: 'لا يجوز',
          operationKey: 'cross',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(
        repo.voidAgreement(a.agreements.single.id, 'إلغاء'),
        throwsA(isA<OfficeFailure>()),
      );
      await repo.voidAllocation(a.allocations.single.id, 'تصحيح تخصيص');
      await repo.voidAgreement(a.agreements.single.id, 'إعادة الاتفاق');
      a = await repo.clientAccount(client);
      expect(a.balance, -50000);
      expect(a.installments.every((i) => i.voidedAt != null), isTrue);
    },
  );

  test(
    'receipt serials are atomic, immutable, reusable on retry, and voided with their payment',
    () async {
      final id = await post('PAYMENT', 10101, key: 'same');
      expect(await post('PAYMENT', 10101, key: 'same'), id);
      final receipts = await Future.wait([
        repo.issueReceipt(id),
        repo.issueReceipt(id),
      ]);
      expect(receipts.map((r) => r.number).toSet(), {1});
      final snapshot = jsonDecode(receipts.first.snapshotJson) as Map;
      expect((snapshot['entry'] as Map)['amountMinor'], 10101);
      var entry = (await repo.clientAccount(client)).entries.single;
      await expectLater(
        repo.changeLedger(
          id,
          expectedRevision: 1,
          amountMinor: 2,
          description: 'تعديل',
          occurredAt: date,
          paymentMethod: 'CASH',
          reason: 'تصحيح',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await repo.changeLedger(
        id,
        expectedRevision: entry.revision,
        amountMinor: entry.amountMinor,
        description: entry.description,
        occurredAt: entry.occurredAt,
        reason: 'إلغاء تجريبي',
        voidEntry: true,
      );
      expect((await repo.readReceipt(1)).voidedAt, isNotNull);
      expect((await repo.clientAccount(client)).balance, 0);
      final replacement = await post('PAYMENT', 10000);
      expect((await repo.issueReceipt(replacement)).number, 2);
      expect(
        (await repo.readReceipt(1)).snapshotJson,
        receipts.first.snapshotJson,
      );
      await expectLater(
        db.customStatement('DELETE FROM financial_receipts'),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "UPDATE financial_receipts SET snapshot_json='{}' WHERE number=2",
        ),
        throwsA(anything),
      );
      final events = await repo.financialHistory('LEDGER', id);
      expect(events.every((e) => e.actorId == ownerId), isTrue);
      expect(events.last.beforeJson, isNotNull);
    },
  );

  test(
    'optimistic edits and injected audit failure cannot silently change money',
    () async {
      final id = await post('FEE', 50000);
      await repo.changeLedger(
        id,
        expectedRevision: 1,
        amountMinor: 45000,
        description: 'تصحيح أتعاب',
        occurredAt: date,
        reason: 'خطأ إدخال',
      );
      await expectLater(
        repo.changeLedger(
          id,
          expectedRevision: 1,
          amountMinor: 1,
          description: 'قديم',
          occurredAt: date,
          reason: 'تعارض',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect((await repo.clientAccount(client)).balance, 45000);
      await db.customStatement(
        "CREATE TRIGGER deny_finance_audit BEFORE INSERT ON audit_log BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(post('PAYMENT', 100), throwsA(anything));
      await expectLater(
        repo.changeLedger(
          id,
          expectedRevision: 2,
          amountMinor: 1,
          description: 'لا يحفظ',
          occurredAt: date,
          reason: 'فشل تدقيق',
        ),
        throwsA(anything),
      );
      expect((await repo.clientAccount(client)).entries, hasLength(1));
      expect((await repo.clientAccount(client)).balance, 45000);
    },
  );

  test(
    'hourly work uses exact integer rounding and unsupported fee models are rejected',
    () async {
      final id = await repo.createAgreement(
        caseId: caseId,
        kind: 'HOURLY',
        amountMinor: 10001,
        terms: 'بالساعة',
        schedule: [],
        operationKey: 'hourly',
      );
      expect((await repo.clientAccount(client)).balance, 0);
      await repo.accrueHours(id, 30, 'بحث', date, 'work');
      expect((await repo.clientAccount(client)).balance, 5001);
      await expectLater(
        repo.createAgreement(
          caseId: caseId,
          kind: 'SUCCESS',
          amountMinor: 100,
          terms: 'نسبة',
          schedule: [],
          operationKey: 'bad',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(post('FEE', -1), throwsA(isA<OfficeFailure>()));
    },
  );

  test(
    'balance overflow rolls back without converting money to floating point',
    () async {
      await post('FEE', 9223372036854775807);
      await expectLater(post('FEE', 1), throwsRangeError);
      expect((await repo.clientAccount(client)).entries, hasLength(1));
      await expectLater(
        post('ADJUSTMENT', -9223372036854775808),
        throwsA(isA<OfficeFailure>()),
      );
    },
  );

  test(
    'legacy classification preserves source/residual, is atomic, and cannot be posted twice',
    () async {
      await db.customStatement('DROP TRIGGER legacy_insert');
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'legacy',
              title: 'أصل قديم',
              amount: 1.005,
              type: 'INCOME',
              transactionDate: Value(date),
            ),
          );
      await db
          .into(db.legacyTransactionReviews)
          .insert(
            LegacyTransactionReviewsCompanion.insert(
              id: 'review',
              legacyTransactionId: 'legacy',
              sourceAmountText: '1.005',
              proposedAmountMinor: const Value(101),
              roundingResidual: const Value('-0.005'),
              hasSubcentPrecision: true,
              isNegative: false,
              ownershipMismatch: false,
            ),
          );
      final input = LedgerInput(
        clientId: client,
        kind: 'PAYMENT',
        amountMinor: 101,
        description: 'تصنيف دفعة قديمة',
        occurredAt: date,
        paymentMethod: 'CASH',
      );
      await expectLater(
        repo.classifyLegacy(
          'review',
          destination: 'LEDGER',
          reason: '',
          ledger: input,
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect(
        (await repo.legacyReviews()).single.review.reviewStatus,
        'PENDING',
      );
      await repo.classifyLegacy(
        'review',
        destination: 'LEDGER',
        reason: 'تم التأكد من الموكل وقبول فرق التقريب',
        ledger: input,
      );
      await expectLater(
        repo.classifyLegacy(
          'review',
          destination: 'LEDGER',
          reason: 'محاولة تكرار',
          ledger: input,
        ),
        throwsA(isA<OfficeFailure>()),
      );
      expect((await db.select(db.transactions).get()).single.amount, 1.005);
      expect(
        (await repo.legacyReviews()).single.review.roundingResidual,
        '-0.005',
      );
      expect((await repo.clientAccount(client)).balance, -101);
      expect(await db.select(db.financialReceipts).get(), isEmpty);
      await expectLater(
        db.customStatement(
          "UPDATE legacy_classifications SET destination='EXCLUDE'",
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'finance requires full client assignment, excludes trainees, and revalidates locked sessions',
    () async {
      final lawyer = await repo.saveStaff(
        const StaffInput(name: 'محامٍ', role: OfficeRole.lawyer),
        initialPin: '671293',
      );
      await repo.assign(
        caseId,
        lawyer,
        forCase: true,
        role: 'LEAD',
        reason: 'إسناد قضية فقط',
      );
      final payment = await post('PAYMENT', 100);
      await repo.issueReceipt(payment);
      await access.signIn(lawyer, '671293');
      await access.changeTemporaryPin(access.session!, '906245');
      await access.signIn(lawyer, '906245');
      final scoped = access.workspace(access.session!);
      await expectLater(
        scoped.clientAccount(client),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(scoped.readReceipt(1), throwsA(isA<OfficeFailure>()));
      await expectLater(
        scoped.financeDashboard(),
        throwsA(isA<OfficeFailure>()),
      );
      await expectLater(scoped.legacyReviews(), throwsA(isA<OfficeFailure>()));
      await access.signIn(ownerId, '481637');
      repo = access.workspace(access.session!);
      await repo.assign(
        client,
        lawyer,
        forCase: false,
        role: 'RESPONSIBLE',
        reason: 'إسناد موكل',
      );
      await access.signIn(lawyer, '906245');
      final granted = access.workspace(access.session!);
      expect((await granted.clientAccount(client)).balance, -100);
      access.lock();
      await expectLater(
        granted.clientAccount(client),
        throwsA(isA<OfficeFailure>()),
      );
    },
  );

  test(
    'offline receipt and long statement PDFs embed Arabic fonts and paginate',
    () async {
      final id = await post('PAYMENT', 12345);
      final receipt = await repo.issueReceipt(id);
      final bytes = await HttpOverrides.runZoned(
        () => FinancePdf.receipt(receipt),
        createHttpClient: (_) => throw StateError('No networking'),
      );
      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
      expect(latin1.decode(bytes), contains('/FontFile2'));
      for (var i = 0; i < 80; i++) {
        await post('FEE', 100 + i);
      }
      final statement = await FinancePdf.statement(
        await repo.clientAccount(client),
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(statement)).length,
        greaterThan(3),
      );
      if (const bool.fromEnvironment('WRITE_SPRINT2_ARTIFACTS')) {
        await Directory('.dart_tool/sprint2').create(recursive: true);
        await File('.dart_tool/sprint2/receipt.pdf').writeAsBytes(bytes);
        await File('.dart_tool/sprint2/statement.pdf').writeAsBytes(statement);
      }
    },
  );

  test(
    'sums are independent of row ordering and preserve exact signed results',
    () {
      const limit = 9223372036854775807;
      expect(checkedSum([limit, 1, -1]), limit);
      expect(checkedSum([-1, limit, 1]), limit);
      expect(() => checkedSum([limit, 1]), throwsRangeError);
    },
  );

  test('competing allocations cannot spend the same credit twice', () async {
    final charge = await post('FEE', 1000, caseRef: caseId);
    final credit = await post('PAYMENT', 1000);
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        repo
            .allocatePayment(
              paymentId: credit,
              chargeId: charge,
              amountMinor: 700,
              reason: 'تخصيص متزامن',
              operationKey: 'race-$i',
            )
            .then<Object>((v) => v)
            .catchError((Object e) => e),
    ]);
    expect(results.whereType<String>(), hasLength(1));
    expect(results.whereType<OfficeFailure>(), hasLength(1));
    final account = await repo.clientAccount(client);
    expect(account.allocated(credit), 700);
    expect(account.caseBalance(caseId), 300);
  });

  test(
    'reminders deduplicate dates, skip settled and void installments, and return after allocation reversal',
    () async {
      await repo.createAgreement(
        caseId: caseId,
        kind: 'FIXED',
        amountMinor: 3000,
        terms: 'اختبار تنبيه',
        schedule: [
          InstallmentInput('أ', 1000, DateTime(2026, 12, 1), reminderDays: 2),
          InstallmentInput('ب', 2000, DateTime(2026, 12, 1), reminderDays: 2),
        ],
        operationKey: 'reminder',
      );
      var a = await repo.clientAccount(client);
      expect(reminderDates(a.installments, a.allocations), [
        DateTime(2026, 11, 29),
      ]);
      final payment = await post('PAYMENT', 3000);
      for (final i in a.installments) {
        await repo.allocatePayment(
          paymentId: payment,
          chargeId: a.entries.single.id,
          installmentId: i.id,
          amountMinor: i.amountMinor,
          reason: 'سداد',
          operationKey: i.id,
        );
      }
      a = await repo.clientAccount(client);
      expect(reminderDates(a.installments, a.allocations), isEmpty);
      await repo.voidAllocation(a.allocations.first.id, 'تصحيح');
      a = await repo.clientAccount(client);
      expect(reminderDates(a.installments, a.allocations), [
        DateTime(2026, 11, 29),
      ]);
    },
  );

  test(
    'office expense corrections and voids are audited without changing client balances',
    () async {
      final id = await repo.saveOfficeExpense(
        amountMinor: 500,
        description: 'انتقال',
        category: 'تشغيل',
        paymentMethod: 'CASH',
        occurredAt: date,
        reason: 'تسجيل',
        operationKey: 'expense-edit',
      );
      await repo.saveOfficeExpense(
        id: id,
        expectedRevision: 1,
        amountMinor: 400,
        description: 'انتقال مصحح',
        category: 'تشغيل',
        paymentMethod: 'CASH',
        occurredAt: date,
        reason: 'إيصال مصحح',
        operationKey: 'unused',
      );
      expect((await repo.financeDashboard()).officeSpent, 400);
      await repo.saveOfficeExpense(
        id: id,
        expectedRevision: 2,
        amountMinor: 400,
        description: 'انتقال مصحح',
        category: 'تشغيل',
        paymentMethod: 'CASH',
        occurredAt: date,
        reason: 'إلغاء',
        operationKey: 'unused',
        voidEntry: true,
      );
      expect((await repo.financeDashboard()).officeSpent, 0);
      expect((await repo.clientAccount(client)).balance, 0);
      expect(await repo.financialHistory('OFFICE_EXPENSE', id), hasLength(3));
      await expectLater(
        db.customStatement('DELETE FROM office_expenses'),
        throwsA(anything),
      );
    },
  );

  test(
    'receipt issuance rolls back its sequence and snapshot if audit cannot be saved',
    () async {
      final payment = await post('PAYMENT', 200);
      await db.customStatement(
        "CREATE TRIGGER deny_receipt_audit BEFORE INSERT ON audit_log WHEN NEW.entity_type='RECEIPT' BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(repo.issueReceipt(payment), throwsA(anything));
      expect(await db.select(db.financialReceipts).get(), isEmpty);
      await db.customStatement('DROP TRIGGER deny_receipt_audit');
      expect((await repo.issueReceipt(payment)).number, 1);
    },
  );

  test(
    'refunded cash cannot be allocated again or funded by a discount',
    () async {
      final payment = await post('PAYMENT', 1000),
          charge = await post('FEE', 1000);
      await post('REFUND', 300);
      await expectLater(
        repo.allocatePayment(
          paymentId: payment,
          chargeId: charge,
          amountMinor: 701,
          reason: 'زيادة',
          operationKey: 'refunded',
        ),
        throwsA(isA<OfficeFailure>()),
      );
      await repo.allocatePayment(
        paymentId: payment,
        chargeId: charge,
        amountMinor: 700,
        reason: 'الباقي',
        operationKey: 'remaining',
      );
      await post('DISCOUNT', 100);
      await expectLater(post('REFUND', 1), throwsA(isA<OfficeFailure>()));
      final a = await repo.clientAccount(client);
      expect(a.refundableCash, 0);
      expect(a.unappliedCredit, 100);
    },
  );

  test(
    'rescheduling preserves original principal, allocations and a before/after audit',
    () async {
      await repo.createAgreement(
        caseId: caseId,
        kind: 'FIXED',
        amountMinor: 1000,
        terms: 'اتفاق',
        schedule: [InstallmentInput('قسط', 1000, DateTime(2026, 12, 1))],
        operationKey: 'reschedule',
      );
      final a = await repo.clientAccount(client),
          i = (await repo.clientAccount(client)).installments.single;
      await repo.rescheduleInstallment(
        i.id,
        expectedRevision: 1,
        label: 'موعد جديد',
        dueAt: DateTime(2027, 1, 3),
        reminderDays: 3,
        reason: 'طلب الموكل',
      );
      final changed = await repo.clientAccount(client);
      expect(changed.balance, a.balance);
      expect(changed.installments.single.amountMinor, 1000);
      expect(reminderDates(changed.installments, changed.allocations), [
        DateTime(2026, 12, 31),
      ]);
      expect(
        (await repo.financialHistory('INSTALLMENT', i.id)).single.beforeJson,
        isNotNull,
      );
      await expectLater(
        repo.rescheduleInstallment(
          i.id,
          expectedRevision: 1,
          label: 'تعارض',
          dueAt: date,
          reminderDays: 1,
          reason: 'قديم',
        ),
        throwsA(isA<OfficeFailure>()),
      );
    },
  );
}
