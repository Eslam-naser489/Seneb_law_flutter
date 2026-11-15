import 'package:seneb_law/core/database/database.dart';

abstract interface class NotesRepository {
  Future<void> addCaseNote({required String caseId, required String content});

  Future<List<CaseNoteEntity>> getCaseNotes(String caseId);
}
