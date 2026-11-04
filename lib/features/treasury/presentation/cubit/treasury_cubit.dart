import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'treasury_state.dart';

class TreasuryCubit extends Cubit<TreasuryState> {
  final AppRepository repository;

  TreasuryCubit(this.repository) : super(TreasuryInitial());

  Future<void> loadTreasuryData() async {
    emit(TreasuryLoading());
    try {
      final transactions = await repository.getAllTransactions();
      final summary = await repository.getTreasurySummary();
      emit(TreasuryLoaded(transactions: transactions, summary: summary));
    } catch (e) {
      emit(TreasuryError(e.toString()));
    }
  }

  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type, // 'INCOME' or 'EXPENSE'
    String? caseId,
    String? clientId,
  }) async {
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
    } catch (e) {
      emit(TreasuryError(e.toString()));
    }
  }
}