import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';
import 'package:seneb_law/core/database/audit_writer.dart';
import '../domain/clients_repository.dart';

class DriftClientsRepository implements ClientsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DriftClientsRepository(this.db);

  @override
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) async {
    final id = _uuid.v4();

    if (name.trim().isEmpty) throw ArgumentError('أدخل اسم الموكل.');
    await db.transaction(() async {
      await db
          .into(db.clients)
          .insert(
            ClientsCompanion.insert(
              id: id,
              name: name.trim(),
              phone: Value(phone?.trim()),
              assignedLawyerId: Value(lawyerId),
            ),
          );
      if (lawyerId != null) {
        await db
            .into(db.clientLawyers)
            .insert(
              ClientLawyersCompanion.insert(
                id: _uuid.v4(),
                clientId: id,
                lawyerId: lawyerId,
                startedAt: Value(DateTime.now().toUtc()),
              ),
            );
      }
    });

    return id;
  }

  @override
  Future<void> updateClient(
    String id, {
    String? name,
    String? phone,
    String? lawyerId,
  }) async {
    await db.transaction(() async {
      if (name != null && name.trim().isEmpty) {
        throw ArgumentError('أدخل اسم الموكل.');
      }
      final old = await (db.select(
        db.clients,
      )..where((t) => t.id.equals(id))).getSingle();
      final now = DateTime.now().toUtc();
      if (lawyerId != null && lawyerId != old.assignedLawyerId) {
        await (db.update(
          db.clientLawyers,
        )..where((t) => t.clientId.equals(id) & t.endedAt.isNull())).write(
          ClientLawyersCompanion(
            endedAt: Value(now),
            updatedAt: Value(now),
            changeReason: const Value(
              'تغيير المحامي المسؤول من الواجهة الحالية',
            ),
          ),
        );
        await db
            .into(db.clientLawyers)
            .insert(
              ClientLawyersCompanion.insert(
                id: _uuid.v4(),
                clientId: id,
                lawyerId: lawyerId,
                startedAt: Value(now),
                changeReason: const Value(
                  'تغيير المحامي المسؤول من الواجهة الحالية',
                ),
              ),
            );
      }
      await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
        ClientsCompanion(
          name: name != null ? Value(name.trim()) : const Value.absent(),
          phone: phone != null ? Value(phone.trim()) : const Value.absent(),
          assignedLawyerId: lawyerId != null
              ? Value(lawyerId)
              : const Value.absent(),
          updatedAt: Value(now),
          revision: Value(old.revision + 1),
        ),
      );
      final changed = await (db.select(
        db.clients,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        db,
        entityType: 'CLIENT',
        entityId: id,
        action: 'UPDATED',
        reason: 'تعديل الموكل من الواجهة الحالية',
        before: old.toJson(),
        after: changed.toJson(),
      );
    });
  }

  @override
  Future<void> archiveClient(String id) async {
    await db.transaction(() async {
      final old = await (db.select(
        db.clients,
      )..where((t) => t.id.equals(id))).getSingle();
      final now = DateTime.now().toUtc();
      await (db.update(db.clients)..where((t) => t.id.equals(id))).write(
        ClientsCompanion(
          isArchived: const Value(true),
          updatedAt: Value(now),
          revision: Value(old.revision + 1),
        ),
      );
      final changed = await (db.select(
        db.clients,
      )..where((t) => t.id.equals(id))).getSingle();
      await recordChange(
        db,
        entityType: 'CLIENT',
        entityId: id,
        action: 'ARCHIVED',
        reason: 'أرشفة الموكل من الواجهة الحالية',
        before: old.toJson(),
        after: changed.toJson(),
      );
    });
  }

  @override
  Future<List<ClientEntity>> getActiveClients() async {
    return await (db.select(
      db.clients,
    )..where((t) => t.isArchived.equals(false))).get();
  }
}
