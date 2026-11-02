import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';

class AppRepository {
  final AppDatabase db;
  final _uuid = const Uuid();

  AppRepository(this.db);

  // ==========================================
  // المحامين
  // ==========================================

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

  // ==========================================
  // الموكلين
  // ==========================================

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

  // ==========================================
  // القضايا
  // ==========================================

  // 1. إضافة قضية جديدة
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
        opponentName: Value(opponentName),
      ),
    );

    return id;
  }

  // 2. جلب كل القضايا مع بيانات الموكلين (Join)
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

  // ==========================================
  // الجلسات (Sessions)
  // ==========================================

  // 1. إضافة جلسة جديدة
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
  }) async {
    final id = _uuid.v4();

    await db.into(db.sessions).insert(
      SessionsCompanion.insert(
        id: id,
        caseId: caseId,
        sessionDate: sessionDate,
        courtLocation: courtLocation,
      ),
    );
  }

  // 2. جلب جلسات اليوم مع بيانات القضية والموكل (Join)
  Future<List<SessionWithDetails>> getTodaySessions() async {
    final now = DateTime.now();

    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final endOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );

    // دمج الجداول الثلاثة معاً
    final query = db.select(db.sessions).join([
      innerJoin(
        db.cases,
        db.cases.id.equalsExp(db.sessions.caseId),
      ),
      innerJoin(
        db.clients,
        db.clients.id.equalsExp(db.cases.clientId),
      ),
    ])
      ..where(
        db.sessions.sessionDate.isBetweenValues(
          startOfDay,
          endOfDay,
        ),
      )
      ..orderBy([
        OrderingTerm.asc(db.sessions.sessionDate),
      ]);

    final rows = await query.get();

    // تحويل النتيجة إلى SessionWithDetails
    return rows.map((row) {
      return SessionWithDetails(
        session: row.readTable(db.sessions),
        caseEntity: row.readTable(db.cases),
        client: row.readTable(db.clients),
      );
    }).toList();
  }

  // ==========================================
  // الملاحظات (Case Notes) وتفاصيل القضية
  // ==========================================

  // 1. إضافة ملاحظة جديدة لملف القضية
  Future<void> addCaseNote({
    required String caseId,
    required String content,
  }) async {
    final id = _uuid.v4();

    await db.into(db.caseNotes).insert(
      CaseNotesCompanion.insert(
        id: id,
        caseId: caseId,
        content: content,
      ),
    );
  }

  // 2. جلب جميع الملاحظات الخاصة بقضية معينة (مرتبة من الأحدث للأقدم)
  Future<List<CaseNoteEntity>> getCaseNotes(String caseId) async {
    return await (db.select(db.caseNotes)
          ..where((t) => t.caseId.equals(caseId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  // 3. جلب جميع الجلسات الخاصة بقضية معينة (لمتابعة سجل جلسات القضية)
  Future<List<SessionEntity>> getCaseSessions(String caseId) async {
    return await (db.select(db.sessions)
          ..where((t) => t.caseId.equals(caseId))
          ..orderBy([(t) => OrderingTerm.asc(t.sessionDate)]))
        .get();
  }
}

// ==========================================
// الكلاسات المساعدة (Helper Classes)
// ==========================================

// القضايا مع بيانات الموكل
class CaseWithClient {
  final CaseEntity caseEntity;
  final ClientEntity client;

  CaseWithClient({
    required this.caseEntity,
    required this.client,
  });
}

// الجلسات مع بيانات القضية والموكل
class SessionWithDetails {
  final SessionEntity session;
  final CaseEntity caseEntity;
  final ClientEntity client;

  SessionWithDetails({
    required this.session,
    required this.caseEntity,
    required this.client,
  });
}
