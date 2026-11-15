import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';
import '../domain/notes_repository.dart';

class DriftNotesRepository implements NotesRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DriftNotesRepository(this.db);

  @override
  Future<void> addCaseNote({
    required String caseId,
    required String content,
  }) async {
    final id = _uuid.v4();

    await db
        .into(db.caseNotes)
        .insert(
          CaseNotesCompanion.insert(id: id, caseId: caseId, content: content),
        );
  }

  @override
  Future<List<CaseNoteEntity>> getCaseNotes(String caseId) async {
    return await (db.select(db.caseNotes)
          ..where((t) => t.caseId.equals(caseId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}
