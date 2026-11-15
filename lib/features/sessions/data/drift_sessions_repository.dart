import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/models.dart';
import 'package:uuid/uuid.dart';
import 'package:seneb_law/core/database/audit_writer.dart';
import '../domain/sessions_repository.dart';

class DriftSessionsRepository implements SessionsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DriftSessionsRepository(this.db);

  @override
  Future<void> updateSessionDecision(
    String sessionId,
    String? decision, {
    required String reason,
  }) => db.transaction(() async {
    if (reason.trim().isEmpty) throw ArgumentError('يجب تسجيل سبب التعديل.');
    final old = await (db.select(
      db.sessions,
    )..where((t) => t.id.equals(sessionId))).getSingle();
    await (db.update(db.sessions)..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        decision: Value(decision?.trim()),
        updatedAt: Value(DateTime.now().toUtc()),
        revision: Value(old.revision + 1),
      ),
    );
    final changed = await (db.select(
      db.sessions,
    )..where((t) => t.id.equals(sessionId))).getSingle();
    await recordChange(
      db,
      entityType: 'SESSION',
      entityId: sessionId,
      action: 'DECISION_CHANGED',
      reason: reason,
      before: old.toJson(),
      after: changed.toJson(),
    );
  });

  @override
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  }) async {
    final id = _uuid.v4();

    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            caseId: caseId,
            sessionDate: sessionDate,
            courtLocation: courtLocation,
            circleNumber: Value(circleNumber?.trim()),
            decision: Value(decision?.trim()),
          ),
        );
  }

  @override
  Future<List<SessionWithDetails>> getTodaySessions() async {
    final now = DateTime.now();

    final startOfDay = DateTime(now.year, now.month, now.day);

    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // دمج الجداول الثلاثة معاً
    final query =
        db.select(db.sessions).join([
            innerJoin(db.cases, db.cases.id.equalsExp(db.sessions.caseId)),
            innerJoin(db.clients, db.clients.id.equalsExp(db.cases.clientId)),
          ])
          ..where(db.sessions.sessionDate.isBetweenValues(startOfDay, endOfDay))
          ..orderBy([OrderingTerm.asc(db.sessions.sessionDate)]);

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

  @override
  Future<List<SessionWithDetails>> getTomorrowSessions() async {
    final now = DateTime.now();
    // نضيف يوم على تاريخ النهارده
    final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
    final endOfTomorrow = DateTime(
      now.year,
      now.month,
      now.day + 1,
      23,
      59,
      59,
      999,
    );

    final query =
        db.select(db.sessions).join([
            innerJoin(db.cases, db.cases.id.equalsExp(db.sessions.caseId)),
            innerJoin(db.clients, db.clients.id.equalsExp(db.cases.clientId)),
          ])
          ..where(
            db.sessions.sessionDate.isBetweenValues(
              startOfTomorrow,
              endOfTomorrow,
            ),
          )
          ..orderBy([OrderingTerm.asc(db.sessions.sessionDate)]);

    final rows = await query.get();

    return rows.map((row) {
      return SessionWithDetails(
        session: row.readTable(db.sessions),
        caseEntity: row.readTable(db.cases),
        client: row.readTable(db.clients),
      );
    }).toList();
  }

  @override
  Future<List<SessionEntity>> getCaseSessions(String caseId) async {
    return await (db.select(db.sessions)
          ..where((t) => t.caseId.equals(caseId))
          ..orderBy([(t) => OrderingTerm.asc(t.sessionDate)]))
        .get();
  }
}
