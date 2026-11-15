import '../../../core/database/database.dart';
import '../../lawyers/domain/office_models.dart';

class ClientProfile {
  const ClientProfile({
    required this.client,
    required this.fullAccess,
    required this.cases,
    required this.sessions,
    required this.notes,
    required this.documents,
    required this.assignments,
    this.history,
  });
  final ClientEntity client;
  final bool fullAccess;
  final List<CaseEntity> cases;
  final List<SessionEntity> sessions;
  final List<CaseNoteEntity> notes;
  final List<CaseDocumentEntity> documents;
  final List<AssignmentView> assignments;
  final List<TransactionEntity>? history;
}

class ClientEdit {
  const ClientEdit(
    this.name,
    this.fields, {
    required this.consent,
    this.consentSource,
  });
  final String name;
  final Map<String, String> fields;
  final String consent;
  final String? consentSource;
}
