import '../../../core/database/database.dart';
import '../../../core/money/money.dart';

const ledgerLabels = {
  'FEE': 'أتعاب مستحقة',
  'PAYMENT': 'دفعة مستلمة',
  'EXPENSE_ADVANCE': 'مصروف مدفوع نيابة عن الموكل',
  'DISCOUNT': 'خصم',
  'REFUND': 'رد مبلغ للموكل',
  'ADJUSTMENT': 'تسوية',
};
const methodLabels = {
  'CASH': 'نقدي',
  'BANK': 'تحويل بنكي',
  'INSTAPAY': 'إنستاباي',
  'CHEQUE': 'شيك محصل',
};
const agreementLabels = {
  'FIXED': 'أتعاب ثابتة',
  'HOURLY': 'بالساعة',
  'MILESTONE': 'على مراحل',
};

int checkedSum(Iterable<int> values) {
  final total = values.fold(
    BigInt.zero,
    (sum, value) => sum + BigInt.from(value),
  );
  // النتيجة لا تتأثر بترتيب الحركات، ولا تتحول إلى عدد عائم.
  if (total.abs() > (BigInt.one << 63) - BigInt.one) {
    throw RangeError('الإجمالي خارج النطاق المالي المسموح.');
  }
  return total.toInt();
}

int ledgerEffect(String kind, int amount) =>
    ['PAYMENT', 'DISCOUNT'].contains(kind) ? -amount : amount;
bool isCharge(ClientLedgerEntry e) =>
    e.voidedAt == null &&
    ['FEE', 'EXPENSE_ADVANCE', 'ADJUSTMENT'].contains(e.kind) &&
    e.amountMinor > 0;
bool isCredit(ClientLedgerEntry e) =>
    e.voidedAt == null &&
    (['PAYMENT', 'DISCOUNT'].contains(e.kind) ||
        (e.kind == 'ADJUSTMENT' && e.amountMinor < 0));
String moneyText(int value) =>
    '${Money.fromMinor(value).toDecimalString()} ج.م';

class LedgerInput {
  const LedgerInput({
    required this.clientId,
    this.caseId,
    required this.kind,
    required this.amountMinor,
    required this.description,
    required this.occurredAt,
    this.paymentMethod,
    this.dueAt,
    this.attributedLawyerId,
  });
  final String clientId;
  final String? caseId;
  final String kind;
  final int amountMinor;
  final String description;
  final DateTime occurredAt;
  final String? paymentMethod;
  final DateTime? dueAt;
  final String? attributedLawyerId;
}

class InstallmentInput {
  const InstallmentInput(
    this.label,
    this.amountMinor,
    this.dueAt, {
    this.reminderDays = 1,
  });
  final String label;
  final int amountMinor;
  final DateTime dueAt;
  final int reminderDays;
}

class ClientAccount {
  ClientAccount(
    this.client,
    this.entries,
    this.agreements,
    this.installments,
    this.allocations,
    this.receipts,
    this.cases,
  );
  final ClientEntity client;
  final List<ClientLedgerEntry> entries;
  final List<FeeAgreement> agreements;
  final List<Installment> installments;
  final List<PaymentAllocation> allocations;
  final List<FinancialReceipt> receipts;
  final List<CaseEntity> cases;
  int get balance => checkedSum(
    entries
        .where((e) => e.voidedAt == null)
        .map((e) => ledgerEffect(e.kind, e.amountMinor)),
  );
  int caseBalance(String id) => checkedSum([
    ...entries
        .where((e) => e.voidedAt == null && e.caseId == id)
        .map((e) => ledgerEffect(e.kind, e.amountMinor)),
    for (final a in allocations.where((a) => a.voidedAt == null))
      if (entries.any((e) => e.id == a.chargeId && e.caseId == id) &&
          entries.any((e) => e.id == a.paymentId && e.caseId == null))
        -a.amountMinor,
  ]);
  int allocated(String id) => checkedSum(
    allocations
        .where(
          (a) => a.voidedAt == null && (a.chargeId == id || a.paymentId == id),
        )
        .map((a) => a.amountMinor),
  );
  int installmentRemaining(Installment i) => i.voidedAt != null
      ? 0
      : i.amountMinor -
            checkedSum(
              allocations
                  .where((a) => a.voidedAt == null && a.installmentId == i.id)
                  .map((a) => a.amountMinor),
            );
  int get unappliedCredit => checkedSum([
    ...entries
        .where(isCredit)
        .map((e) => e.amountMinor.abs() - allocated(e.id)),
    ...entries
        .where((e) => e.voidedAt == null && e.kind == 'REFUND')
        .map((e) => -e.amountMinor),
  ]);
  int get refundableCash => checkedSum([
    ...entries
        .where((e) => e.voidedAt == null && e.kind == 'PAYMENT')
        .map((e) => e.amountMinor - allocated(e.id)),
    ...entries
        .where((e) => e.voidedAt == null && e.kind == 'REFUND')
        .map((e) => -e.amountMinor),
  ]);
}

class FinanceDashboard {
  const FinanceDashboard({
    required this.accounts,
    required this.expenses,
    required this.pendingLegacy,
  });
  final List<ClientAccount> accounts;
  final List<OfficeExpense> expenses;
  final int pendingLegacy;
  Iterable<ClientLedgerEntry> get active =>
      accounts.expand((a) => a.entries).where((e) => e.voidedAt == null);
  int get collected => checkedSum(
    active.where((e) => e.kind == 'PAYMENT').map((e) => e.amountMinor),
  );
  int get refunded => checkedSum(
    active.where((e) => e.kind == 'REFUND').map((e) => e.amountMinor),
  );
  int get costs => checkedSum(
    active.where((e) => e.kind == 'EXPENSE_ADVANCE').map((e) => e.amountMinor),
  );
  int get officeSpent => checkedSum(
    expenses.where((e) => e.voidedAt == null).map((e) => e.amountMinor),
  );
  int get cashMovement =>
      checkedSum([collected, -refunded, -costs, -officeSpent]);
  Map<String, int> get collectedByLawyer => _group(
    active.where((e) => ['PAYMENT', 'REFUND'].contains(e.kind)),
    (e) => e.attributedLawyerId,
    (e) => e.kind == 'REFUND' ? -e.amountMinor : e.amountMinor,
  );
  Map<String, int> get monthlyNet => _group(
    active.where(
      (e) => ['PAYMENT', 'REFUND', 'EXPENSE_ADVANCE'].contains(e.kind),
    ),
    (e) => monthKey(e.occurredAt),
    (e) => e.kind == 'PAYMENT' ? e.amountMinor : -e.amountMinor,
  )..addEntries(_monthlyOfficeEntries());
  Iterable<MapEntry<String, int>> _monthlyOfficeEntries() sync* {
    final base = _group(
      active.where(
        (e) => ['PAYMENT', 'REFUND', 'EXPENSE_ADVANCE'].contains(e.kind),
      ),
      (e) => monthKey(e.occurredAt),
      (e) => e.kind == 'PAYMENT' ? e.amountMinor : -e.amountMinor,
    );
    final office = <String, int>{};
    for (final e in expenses.where((e) => e.voidedAt == null)) {
      final key = monthKey(e.occurredAt);
      office[key] = checkedSum([office[key] ?? 0, e.amountMinor]);
    }
    for (final e in office.entries) {
      yield MapEntry(e.key, checkedSum([base[e.key] ?? 0, -e.value]));
    }
  }

  // أعمار ديون حصرية. جدول الأقساط يستبدل تاريخ استحقاق أصل الأتعاب.
  Map<String, int> aging(DateTime now) {
    final buckets = {'1–30': 0, '31–60': 0, '61–90': 0, '90+': 0};
    void add(DateTime due, int amount) {
      final today = DateTime.utc(now.year, now.month, now.day);
      final date = DateTime.utc(due.year, due.month, due.day);
      final days = today.difference(date).inDays;
      if (days <= 0 || amount <= 0) return;
      final key = days <= 30
          ? '1–30'
          : days <= 60
          ? '31–60'
          : days <= 90
          ? '61–90'
          : '90+';
      buckets[key] = checkedSum([buckets[key]!, amount]);
    }

    for (final a in accounts) {
      for (final i in a.installments.where((i) => i.voidedAt == null)) {
        add(i.dueAt, a.installmentRemaining(i));
      }
      for (final e in a.entries.where(isCharge)) {
        if (e.dueAt != null &&
            !a.installments.any(
              (i) => i.chargeId == e.id && i.voidedAt == null,
            )) {
          add(e.dueAt!, e.amountMinor - a.allocated(e.id));
        }
      }
    }
    return buckets;
  }

  static String monthKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}';
  static Map<String, int> _group(
    Iterable<ClientLedgerEntry> entries,
    String Function(ClientLedgerEntry) key,
    int Function(ClientLedgerEntry) value,
  ) {
    final result = <String, int>{};
    for (final e in entries) {
      final k = key(e);
      result[k] = checkedSum([result[k] ?? 0, value(e)]);
    }
    return result;
  }
}

class LegacyReviewItem {
  const LegacyReviewItem(this.review, this.source, this.classification);
  final LegacyTransactionReview review;
  final TransactionEntity source;
  final LegacyClassification? classification;
}
