import 'package:seneb_law/core/database/database.dart';

abstract interface class TreasuryRepository {
  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type, // 'INCOME' أو 'EXPENSE'
    String? caseId,
    String? clientId,
  });

  Future<List<TransactionEntity>> getAllTransactions();

  Future<Map<String, double>> getTreasurySummary();

  Future<List<TransactionEntity>> getCaseTransactions(String caseId);
}
