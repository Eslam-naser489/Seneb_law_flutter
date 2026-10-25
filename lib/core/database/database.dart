import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// 1. جدول محامين المكتب (Lawyers)
@DataClassName('OfficeLawyerEntity')
class OfficeLawyers extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
}

// 2. جدول الموكلين (Clients)
@DataClassName('ClientEntity')
class Clients extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  // Foreign Key: ربط الموكل بالمحامي المسؤول
  TextColumn get assignedLawyerId => text().nullable().references(OfficeLawyers, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}

// 3. جدول القضايا (Cases)
@DataClassName('CaseEntity')
class Cases extends Table {
  TextColumn get id => text()(); // UUID
  // Foreign Key: ربط القضية بالموكل
  TextColumn get clientId => text().references(Clients, #id)(); 
  TextColumn get caseNumber => text()();
  TextColumn get opponentName => text().nullable()();
  // حالة القضية (جارية، منتهية، إلخ)
  TextColumn get status => text().withDefault(const Constant('جارية'))(); 
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}

// 4. جدول الجلسات (Sessions/Hearings)
@DataClassName('SessionEntity')
class Sessions extends Table {
  TextColumn get id => text()(); // UUID
  // Foreign Key: ربط الجلسة بالقضية
  TextColumn get caseId => text().references(Cases, #id)(); 
  DateTimeColumn get sessionDate => dateTime()();
  TextColumn get courtLocation => text()();
  TextColumn get circleNumber => text().nullable()();
  TextColumn get decision => text().nullable()(); // القرار في الجلسة (مؤجلة لـ كذا)
  
  @override
  Set<Column> get primaryKey => {id};
}

// 5. جدول الملاحظات والتطورات (Case Notes)
@DataClassName('CaseNoteEntity')
class CaseNotes extends Table {
  TextColumn get id => text()(); // UUID
  // Foreign Key: ربط الملاحظة بالقضية
  TextColumn get caseId => text().references(Cases, #id)(); 
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}

// تجميع كل الجداول في قاعدة البيانات
@DriftDatabase(tables: [OfficeLawyers, Clients, Cases, Sessions, CaseNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // تفعيل الـ Foreign Keys في SQLite عشان العلاقات تشتغل صح
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