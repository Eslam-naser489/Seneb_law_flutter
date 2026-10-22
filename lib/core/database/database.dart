import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// جدول مبدئي للموكلين (لتجربة قاعدة البيانات)
@DataClassName('ClientEntity')
class Clients extends Table {
  TextColumn get id => text()(); // UUID String to avoid cross-device conflicts
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Clients])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

// دالة لإنشاء ملف قاعدة البيانات في مكان آمن داخل نظام التشغيل (ويندوز أو أندرويد)
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // جلب مسار المستندات الخاص بالمستخدم
    final dbFolder = await getApplicationDocumentsDirectory();
    // إنشاء ملف الداتابيز باسم seneb_law_db.sqlite
    final file = File(p.join(dbFolder.path, 'seneb_law', 'seneb_law_db.sqlite'));
    
    return NativeDatabase.createInBackground(file);
  });
}