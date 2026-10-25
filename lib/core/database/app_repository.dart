import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';

class AppRepository {
  final AppDatabase db;
  final _uuid = const Uuid();

  AppRepository(this.db);

  // ==================== المحامين ====================
  Future<String> addLawyer(String name) async {
    final id = _uuid.v4();
    await db.into(db.officeLawyers).insert(OfficeLawyersCompanion.insert(id: id, name: name));
    return id;
  }

  Future<List<OfficeLawyerEntity>> getLawyers() async {
    return await db.select(db.officeLawyers).get();
  }

  // ==================== الموكلين ====================
  // 1. إضافة موكل
  Future<String> addClient({required String name, String? phone, String? lawyerId}) async {
    final id = _uuid.v4();
    await db.into(db.clients).insert(
      ClientsCompanion.insert(
        id: id,
        name: name,
        phone: Value(phone),
        assignedLawyerId: Value(lawyerId),
      ),
    );
    return id;
  }

  // 2. تعديل موكل (بما فيها تغيير المحامي)
  Future<void> updateClient(String id, {String? name, String? phone, String? lawyerId}) async {
    await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        phone: phone != null ? Value(phone) : const Value.absent(),
        // لو بعتنا أيدي محامي جديد هيتغير هنا
        assignedLawyerId: lawyerId != null ? Value(lawyerId) : const Value.absent(),
      ),
    );
  }

  // 3. أرشفة موكل (بدل الحذف النهائي لحماية البيانات المالية)
  Future<void> archiveClient(String id) async {
    await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
      const ClientsCompanion(isArchived: Value(true)),
    );
  }

  // 4. جلب الموكلين النشطين فقط
  Future<List<ClientEntity>> getActiveClients() async {
    return await (db.select(db.clients)..where((t) => t.isArchived.equals(false))).get();
  }
}