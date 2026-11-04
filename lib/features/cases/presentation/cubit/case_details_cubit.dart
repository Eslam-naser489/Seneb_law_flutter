import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'case_details_state.dart';

class CaseDetailsCubit extends Cubit<CaseDetailsState> {
  final AppRepository repository;

  CaseDetailsCubit(this.repository) : super(CaseDetailsInitial());

  Future<void> loadCaseDetails(String caseId) async {
    if (isClosed) return;
    emit(CaseDetailsLoading());
    try {
      final sessions = await repository.getCaseSessions(caseId);
      final notes = await repository.getCaseNotes(caseId);
      final transactions = await repository.getCaseTransactions(caseId);
      final documents = await repository.getCaseDocuments(caseId); // الجديد

      if (isClosed) return;
      emit(
        CaseDetailsLoaded(
          sessions: sessions,
          notes: notes,
          transactions: transactions,
          documents: documents, // الجديد
        ),
      );
    } catch (e) {
      if (!isClosed) emit(CaseDetailsError(e.toString()));
    }
  }

  Future<void> addCaseNote(String caseId, String content) async {
    try {
      await repository.addCaseNote(caseId: caseId, content: content);
      await loadCaseDetails(caseId);
    } catch (e) {
      if (!isClosed) emit(CaseDetailsError(e.toString()));
    }
  }

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
        type: 'INCOME',
        caseId: caseId,
        clientId: clientId,
      );
      await loadCaseDetails(caseId);
    } catch (e) {
      if (!isClosed) emit(CaseDetailsError(e.toString()));
    }
  }

  // الجديد: إضافة مستند للأرشيف
  Future<void> addDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  }) async {
    try {
      await repository.addCaseDocument(
        caseId: caseId,
        title: title,
        filePath: filePath,
        fileType: fileType,
      );
      await loadCaseDetails(caseId); // تحديث الشاشة
    } catch (e) {
      if (!isClosed) emit(CaseDetailsError(e.toString()));
    }
  }
}
