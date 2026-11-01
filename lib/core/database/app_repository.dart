import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';

class AppRepository {
  final AppDatabase db;
  final _uuid = const Uuid();

  AppRepository(this.db);

  //  المحامين 

  Future<String> addLawyer(String name) async {
    final id = _uuid.v4();

    await db.into(db.officeLawyers).insert(
      OfficeLawyersCompanion.insert(
        id: id,
        name: name,
      ),
    );

    return id;
  }

  Future<List<OfficeLawyerEntity>> getLawyers() async {
    return await db.select(db.officeLawyers).get();
  }

  // الموكلين 

  // 1. إضافة موكل
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) async {
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

  // 2. تعديل موكل
  Future<void> updateClient(
    String id, {
    String? name,
    String? phone,
    String? lawyerId,
  }) async {
    await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        phone: phone != null ? Value(phone) : const Value.absent(),
        assignedLawyerId:
            lawyerId != null ? Value(lawyerId) : const Value.absent(),
      ),
    );
  }

  // 3. أرشفة موكل
  Future<void> archiveClient(String id) async {
    await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
      const ClientsCompanion(
        isArchived: Value(true),
      ),
    );
  }

  // 4. جلب الموكلين النشطين فقط
  Future<List<ClientEntity>> getActiveClients() async {
    return await (db.select(db.clients)
          ..where((t) => t.isArchived.equals(false)))
        .get();
  }

  //  القضايا 
// إضافة قضية جديدة
Future<String> addCase({
  required String clientId,
  required String caseNumber,
  String? opponentName,
}) async {
  final id = _uuid.v4();

  await db.into(db.cases).insert(
    CasesCompanion.insert(
      id: id,
      clientId: clientId,
      caseNumber: caseNumber,
      opponentName: Value(opponentName), // نستخدم Value لأن الحقل يقبل null
    ),
  );

  return id;
}
  // جلب كل القضايا مع بيانات الموكلين (Join)
  Future<List<CaseWithClient>> getCasesWithClients() async {
    final query = db.select(db.cases).join([
      innerJoin(
        db.clients,
        db.clients.id.equalsExp(db.cases.clientId),
      ),
    ])..orderBy([
        OrderingTerm.desc(db.cases.createdAt),
      ]);

    final rows = await query.get();

    return rows.map((row) {
      return CaseWithClient(
        caseEntity: row.readTable(db.cases),
        client: row.readTable(db.clients),
      );
    }).toList();
  }
}

// القضايا مع بيانات الموك

class CaseWithClient {
  final CaseEntity caseEntity;
  final ClientEntity client;

  CaseWithClient({
    required this.caseEntity,
    required this.client,
  });
}