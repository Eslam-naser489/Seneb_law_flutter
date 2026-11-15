part of 'database.dart';

mixin LifecycleColumns on Table {
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
}

class ClientLawyers extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get lawyerId => text().references(OfficeLawyers, #id)();
  TextColumn get assignmentRole =>
      text().withDefault(const Constant('RESPONSIBLE'))();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get changeReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class CaseLawyers extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)();
  TextColumn get lawyerId => text().references(OfficeLawyers, #id)();
  TextColumn get assignmentRole => text().customConstraint(
    "NOT NULL CHECK (assignment_role IN ('LEAD', 'ASSISTANT'))",
  )();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get changeReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalCredentials extends Table {
  TextColumn get id => text()();
  TextColumn get lawyerId => text().unique().references(OfficeLawyers, #id)();
  TextColumn get pinVerifier => text()();
  TextColumn get algorithm => text()();
  TextColumn get parametersJson => text()();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  BoolColumn get mustChangePin => boolean().withDefault(const Constant(true))();
  IntColumn get credentialsVersion =>
      integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class AuditLog extends Table {
  TextColumn get id => text()();
  TextColumn get actorId => text().nullable().references(OfficeLawyers, #id)();
  TextColumn get actorKind => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get operationId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get scopeOwnerId =>
      text().nullable().references(OfficeLawyers, #id)();
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class LegacyTransactionReviews extends Table {
  TextColumn get id => text()();
  TextColumn get legacyTransactionId =>
      text().unique().references(Transactions, #id)();
  TextColumn get sourceAmountText => text()();
  IntColumn get proposedAmountMinor => integer().nullable()();
  TextColumn get roundingResidual => text().nullable()();
  TextColumn get conversionError => text().nullable()();
  BoolColumn get hasSubcentPrecision => boolean()();
  BoolColumn get isNegative => boolean()();
  BoolColumn get ownershipMismatch => boolean()();
  TextColumn get reviewStatus =>
      text().withDefault(const Constant('PENDING'))();
  TextColumn get reviewedBy =>
      text().nullable().references(OfficeLawyers, #id)();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}
