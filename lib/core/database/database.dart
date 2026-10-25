import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

@DataClassName('OfficeLawyerEntity')
class OfficeLawyers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ClientEntity')
class Clients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get assignedLawyerId => text().nullable().references(OfficeLawyers, #id)();
  // حقل الأرشفة (الافتراضي: غير مؤرشف)
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CaseEntity')
class Cases extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)(); 
  TextColumn get caseNumber => text()();
  TextColumn get opponentName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('جارية'))(); 
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SessionEntity')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)(); 
  DateTimeColumn get sessionDate => dateTime()();
  TextColumn get courtLocation => text()();
  TextColumn get circleNumber => text().nullable()();
  TextColumn get decision => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CaseNoteEntity')
class CaseNotes extends Table {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)(); 
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [OfficeLawyers, Clients, Cases, Sessions, CaseNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  // Constructor مخصص للـ Testing
  AppDatabase.forTesting(super.connection); 

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'seneb_law', 'seneb_law_db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}