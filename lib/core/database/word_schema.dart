part of 'database.dart';

class WordTemplates extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get version => integer()();
  BlobColumn get bytes => blob()();
  TextColumn get checksum => text()();
  TextColumn get fieldsJson => text()();
  TextColumn get createdBy => text().references(OfficeLawyers, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {name, version},
  ];
}

/// تخزين ذري داخل القاعدة يشمل القوالب والملفات في النسخ الاحتياطية.
class WordDocuments extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get operationKey => text().unique()();
  TextColumn get templateId => text().references(WordTemplates, #id)();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get caseId => text().nullable().references(Cases, #id)();
  TextColumn get title => text()();
  TextColumn get inputJson => text()();
  TextColumn get sourceHash => text()();
  BlobColumn get bytes => blob()();
  TextColumn get checksum => text()();
  TextColumn get createdBy => text().references(OfficeLawyers, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class WordShareAttempts extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(WordDocuments, #id)();
  TextColumn get actorId => text().references(OfficeLawyers, #id)();
  TextColumn get channel => text()();
  TextColumn get checksum => text()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK(status IN ('STARTED','OPENED','SAVED','CANCELLED','FAILED','UNAVAILABLE'))",
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}
