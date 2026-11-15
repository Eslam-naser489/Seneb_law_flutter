import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/models.dart';

abstract interface class SessionsRepository {
  Future<void> updateSessionDecision(
    String sessionId,
    String? decision, {
    required String reason,
  });
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  });

  Future<List<SessionWithDetails>> getTodaySessions();

  Future<List<SessionWithDetails>> getTomorrowSessions();

  Future<List<SessionEntity>> getCaseSessions(String caseId);
}
