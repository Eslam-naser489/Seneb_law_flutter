import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/app_repository.dart';

void main() {
  late AppDatabase db;
  late AppRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    repository = AppRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('should add, update lawyer, and archive client correctly', () async {
    // 1. إضافة 2 محامين
    final lawyer1Id = await repository.addLawyer('محامي أ');
    final lawyer2Id = await repository.addLawyer('محامي ب');

    // 2. إضافة موكل وربطه بالمحامي الأول
    final clientId = await repository.addClient(name: 'إسلام ناصر', lawyerId: lawyer1Id);
    
    var activeClients = await repository.getActiveClients();
    expect(activeClients.length, 1);
    expect(activeClients.first.assignedLawyerId, lawyer1Id); // التأكد إنه مربوط بالمحامي الأول

    // 3. تعديل الموكل لتغيير المحامي للمحامي الثاني
    await repository.updateClient(clientId, lawyerId: lawyer2Id);
    
    activeClients = await repository.getActiveClients();
    expect(activeClients.first.assignedLawyerId, lawyer2Id); // التأكد إن المحامي اتغير بنجاح

    // 4. أرشفة الموكل (بدل مسحه)
    await repository.archiveClient(clientId);
    
    activeClients = await repository.getActiveClients();
    expect(activeClients.isEmpty, true); // التأكد إن القائمة النشطة بقت فاضية لأن الموكل اتأرشف
  });
}