part of 'database.dart';

class ReportTemplates extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get body => text()();
  TextColumn get fieldLabel => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class CaseReports extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get operationKey => text().unique()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get caseId => text().nullable().references(Cases, #id)();
  TextColumn get sourceKind => text().customConstraint(
    "NOT NULL CHECK(source_kind IN ('REPORT','RECEIPT','STATEMENT'))",
  )();
  IntColumn get receiptNumber => integer().nullable()();
  TextColumn get createdBy => text().references(OfficeLawyers, #id)();
  TextColumn get snapshotJson => text()();
  TextColumn get textContent => text()();
  TextColumn get contentHash => text()();
  BoolColumn get includesFinance => boolean()();
  DateTimeColumn get previewedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// تحفظ الملفات داخل النسخة المحلية لتشملها النسخ الاحتياطية تلقائيًا.
class GeneratedDocuments extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get reportId => text().references(CaseReports, #id)();
  TextColumn get format =>
      text().customConstraint("NOT NULL CHECK(format IN ('PDF','PNG'))")();
  IntColumn get pageNumber => integer()();
  BlobColumn get bytes => blob()();
  TextColumn get contentHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {reportId, format, pageNumber},
  ];
}

class ShareAttempts extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get reportId => text().references(CaseReports, #id)();
  TextColumn get actorId => text().references(OfficeLawyers, #id)();
  TextColumn get channel => text()();
  TextColumn get format => text()();
  TextColumn get recipientSnapshot => text()();
  TextColumn get contentHash => text()();
  TextColumn get artifactHashesJson => text()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK(status IN ('STARTED','OPENED','CANCELLED','FAILED','UNAVAILABLE','SAVED','COPIED'))",
  )();
  TextColumn get actualTarget => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  DateTimeColumn get userConfirmedSentAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}
