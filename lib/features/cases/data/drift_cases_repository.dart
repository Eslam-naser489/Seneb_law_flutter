import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/models.dart';
import 'package:uuid/uuid.dart';
import 'package:seneb_law/core/database/audit_writer.dart';
import '../domain/cases_repository.dart';

class DriftCasesRepository implements CasesRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DriftCasesRepository(this.db);

  @override
  Future<void> updateCaseStatus(
    String caseId,
    String statusCode, {
    required String reason,
  }) => db.transaction(() async {
    const labels = {
      'ACTIVE': 'جارية',
      'CLOSED': 'منتهية',
      'ON_HOLD': 'موقوفة',
      'ARCHIVED': 'مؤرشفة',
    };
    if (!labels.containsKey(statusCode) || reason.trim().isEmpty) {
      throw ArgumentError('راجع الحالة وسبب التغيير.');
    }
    final old = await (db.select(
      db.cases,
    )..where((t) => t.id.equals(caseId))).getSingle();
    await (db.update(db.cases)..where((t) => t.id.equals(caseId))).write(
      CasesCompanion(
        status: Value(labels[statusCode]!),
        statusCode: Value(statusCode),
        updatedAt: Value(DateTime.now().toUtc()),
        revision: Value(old.revision + 1),
      ),
    );
    final changed = await (db.select(
      db.cases,
    )..where((t) => t.id.equals(caseId))).getSingle();
    await recordChange(
      db,
      entityType: 'CASE',
      entityId: caseId,
      action: 'STATUS_CHANGED',
      reason: reason,
      before: old.toJson(),
      after: changed.toJson(),
    );
  });

  @override
  Future<String> addCase({
    required String clientId,
    required String caseNumber,
    String? opponentName,
  }) async {
    final id = _uuid.v4();

    await db
        .into(db.cases)
        .insert(
          CasesCompanion.insert(
            id: id,
            clientId: clientId,
            caseNumber: caseNumber,
            opponentName: Value(opponentName),
          ),
        );

    return id;
  }

  @override
  Future<List<CaseWithClient>> getCasesWithClients() async {
    final query = db.select(db.cases).join([
      innerJoin(db.clients, db.clients.id.equalsExp(db.cases.clientId)),
    ])..orderBy([OrderingTerm.desc(db.cases.createdAt)]);

    final rows = await query.get();

    return rows.map((row) {
      return CaseWithClient(
        caseEntity: row.readTable(db.cases),
        client: row.readTable(db.clients),
      );
    }).toList();
  }
}
