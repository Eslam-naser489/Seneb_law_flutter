import 'database.dart';

class CaseWithClient {
  final CaseEntity caseEntity;
  final ClientEntity client;

  CaseWithClient({required this.caseEntity, required this.client});
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
