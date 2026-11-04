import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'case_details_state.dart';

class CaseDetailsCubit extends Cubit<CaseDetailsState> {
  final AppRepository repository;

  CaseDetailsCubit(this.repository) : super(CaseDetailsInitial());

  Future<void> loadCaseDetails(String caseId) async {
    emit(CaseDetailsLoading());
    try {
      final sessions = await repository.getCaseSessions(caseId);
      final notes = await repository.getCaseNotes(caseId);
      final transactions = await repository.getCaseTransactions(caseId); // الجديد
      
      emit(CaseDetailsLoaded(
        sessions: sessions,
        notes: notes,
        transactions: transactions, // الجديد
      ));
    } catch (e) {
      emit(CaseDetailsError(e.toString()));
    }
  }

  Future<void> addCaseNote(String caseId, String content) async {
    try {
      await repository.addCaseNote(caseId: caseId, content: content);
      await loadCaseDetails(caseId);
    } catch (e) {
      emit(CaseDetailsError(e.toString()));
    }
  }

  // الجديد: إضافة دفعة أتعاب للقضية
  Future<void> addCasePayment({
    required String caseId,
    required String clientId,
    required String title,
    required double amount,
  }) async {
    try {
      await repository.addTransaction(
        title: title,
        amount: amount,
        type: 'INCOME', // الأتعاب دائماً إيراد
        caseId: caseId,
        clientId: clientId,
      );
      await loadCaseDetails(caseId); // تحديث الشاشة
    } catch (e) {
      emit(CaseDetailsError(e.toString()));
    }
  }
}