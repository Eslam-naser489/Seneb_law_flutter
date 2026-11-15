import 'package:drift/drift.dart';
import 'package:seneb_law/core/database/database.dart';
import '../domain/treasury_repository.dart';

class DriftTreasuryRepository implements TreasuryRepository {
  final AppDatabase db;
  DriftTreasuryRepository(this.db);

  @override
  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type, // 'INCOME' أو 'EXPENSE'
    String? caseId,
    String? clientId,
  }) async {
    throw StateError(
      'المعاملات القديمة للقراءة فقط حتى مراجعة التصنيف وتفعيل الحسابات الجديدة.',
    );
  }

  @override
  Future<List<TransactionEntity>> getAllTransactions() async {
    return await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.desc(t.transactionDate)])).get();
  }

  @override
  Future<Map<String, double>> getTreasurySummary() async {
    final transactions = await getAllTransactions();
    double totalIncome = 0;
    double totalExpense = 0;

    for (var t in transactions) {
      if (t.type == 'INCOME') {
        totalIncome += t.amount;
      } else if (t.type == 'EXPENSE') {
        totalExpense += t.amount;
      }
    }

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'net': totalIncome - totalExpense, // الصافي
    };
  }

  @override
  Future<List<TransactionEntity>> getCaseTransactions(String caseId) async {
    return await (db.select(db.transactions)
          ..where((t) => t.caseId.equals(caseId))
          ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
        .get();
  }
}
