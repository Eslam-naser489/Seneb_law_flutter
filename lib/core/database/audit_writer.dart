import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

final auditActorKey = Object();

Future<void> recordChange(
  AppDatabase db, {
  required String entityType,
  required String entityId,
  required String action,
  required String reason,
  String? actorId,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) async {
  if (reason.trim().isEmpty) throw ArgumentError('يجب تسجيل سبب التغيير.');
  final actor = actorId ?? Zone.current[auditActorKey] as String?;
  await db
      .into(db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          id: const Uuid().v4(),
          actorKind: actor == null ? 'LEGACY_LOCAL' : 'STAFF',
          actorId: Value(actor),
          entityType: entityType,
          entityId: entityId,
          action: action,
          reason: reason.trim(),
          beforeJson: Value(before == null ? null : jsonEncode(before)),
          afterJson: Value(after == null ? null : jsonEncode(after)),
          operationId: const Uuid().v4(),
        ),
      );
}
