import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'treasury_state.dart';

class TreasuryCubit extends Cubit<TreasuryState> {
  final AppRepository repository;
  bool _saving = false;

  TreasuryCubit(this.repository) : super(TreasuryInitial());

  Future<void> loadTreasuryData() async {
    if (!isClosed) emit(TreasuryLoading());
    try {
      final transactions = await repository.getAllTransactions();
      final summary = await repository.getTreasurySummary();
      if (!isClosed) {
        emit(TreasuryLoaded(transactions: transactions, summary: summary));
      }
    } catch (e) {
      if (!isClosed) emit(TreasuryError('تعذر تحميل الخزينة. حاول مرة أخرى.'));
    }
  }

  Future<bool> addTransaction({
    required String title,
    required double amount,
    required String type, // 'INCOME' or 'EXPENSE'
    String? caseId,
    String? clientId,
  }) async {
    if (_saving || isClosed) return false;
    _saving = true;
    try {
      await repository.addTransaction(
        title: title,
        amount: amount,
        type: type,
        caseId: caseId,
        clientId: clientId,
      );
      // تحديث الخزينة فورا بعد أي حركة
      await loadTreasuryData();
      return true;
    } catch (e) {
      return false;
    } finally {
      _saving = false;
    }
  }
}
