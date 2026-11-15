import 'package:seneb_law/core/database/models.dart';

abstract interface class CasesRepository {
  Future<void> updateCaseStatus(
    String caseId,
    String statusCode, {
    required String reason,
  });
  Future<String> addCase({
    required String clientId,
    required String caseNumber,
    String? opponentName,
  });

  Future<List<CaseWithClient>> getCasesWithClients();
}
