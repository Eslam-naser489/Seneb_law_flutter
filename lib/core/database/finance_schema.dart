part of 'database.dart';

mixin FinancialColumns on Table {
  TextColumn get id => text()();
  TextColumn get currency => text().customConstraint(
    "NOT NULL DEFAULT 'EGP' CHECK(currency = 'EGP')",
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
  TextColumn get createdBy => text().references(OfficeLawyers, #id)();
  @override
  Set<Column> get primaryKey => {id};
}

class ClientLedgerEntries extends Table with FinancialColumns {
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get caseId => text().nullable().references(Cases, #id)();
  TextColumn get kind => text().customConstraint(
    "NOT NULL CHECK(kind IN ('FEE','PAYMENT','EXPENSE_ADVANCE','DISCOUNT','REFUND','ADJUSTMENT'))",
  )();
  // التسوية وحدها تسمح بقيمة سالبة. بقية الأنواع تحمل مقدارًا موجبًا.
  IntColumn get amountMinor => integer().customConstraint(
    "NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor != 0 AND (kind = 'ADJUSTMENT' OR amount_minor > 0))",
  )();
  TextColumn get description => text()();
  TextColumn get paymentMethod => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get agreementId =>
      text().nullable().references(FeeAgreements, #id)();
  @ReferenceName('attributedEntries')
  TextColumn get attributedLawyerId => text().references(OfficeLawyers, #id)();
  TextColumn get operationKey => text().unique()();
}

class FeeAgreements extends Table with FinancialColumns {
  TextColumn get caseId => text().references(Cases, #id)();
  TextColumn get kind => text().customConstraint(
    "NOT NULL CHECK(kind IN ('FIXED','HOURLY','MILESTONE'))",
  )();
  IntColumn get amountMinor => integer().customConstraint(
    "NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor > 0)",
  )();
  TextColumn get terms => text()();
  TextColumn get operationKey => text().unique()();
}

class Installments extends Table with FinancialColumns {
  TextColumn get agreementId => text().references(FeeAgreements, #id)();
  TextColumn get chargeId => text().references(ClientLedgerEntries, #id)();
  TextColumn get label => text()();
  IntColumn get amountMinor => integer().customConstraint(
    "NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor > 0)",
  )();
  DateTimeColumn get dueAt => dateTime()();
  IntColumn get reminderDays => integer().withDefault(const Constant(1))();
}

class PaymentAllocations extends Table with FinancialColumns {
  @ReferenceName('creditAllocations')
  TextColumn get paymentId => text().references(ClientLedgerEntries, #id)();
  TextColumn get chargeId => text().references(ClientLedgerEntries, #id)();
  TextColumn get installmentId =>
      text().nullable().references(Installments, #id)();
  IntColumn get amountMinor => integer().customConstraint(
    "NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor > 0)",
  )();
  TextColumn get operationKey => text().unique()();
}

class OfficeExpenses extends Table with FinancialColumns {
  IntColumn get amountMinor => integer().customConstraint(
    "NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor > 0)",
  )();
  TextColumn get description => text()();
  TextColumn get category => text()();
  TextColumn get paymentMethod => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get operationKey => text().unique()();
}

class FinancialReceipts extends Table {
  IntColumn get number => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get entryId => text().references(ClientLedgerEntries, #id)();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get createdBy => text().references(OfficeLawyers, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
}

class LegacyClassifications extends Table {
  TextColumn get id => text()();
  TextColumn get reviewId =>
      text().unique().references(LegacyTransactionReviews, #id)();
  TextColumn get destination => text()();
  TextColumn get ledgerEntryId =>
      text().nullable().references(ClientLedgerEntries, #id)();
  TextColumn get officeExpenseId =>
      text().nullable().references(OfficeExpenses, #id)();
  TextColumn get reason => text()();
  TextColumn get reviewedBy => text().references(OfficeLawyers, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}
