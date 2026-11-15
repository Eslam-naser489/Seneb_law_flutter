import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'case_details_state.dart';

class CaseDetailsCubit extends Cubit<CaseDetailsState> {
  final AppRepository repository;
  bool _saving = false;

  CaseDetailsCubit(this.repository) : super(CaseDetailsInitial());

  Future<void> loadCaseDetails(String caseId) async {
    if (isClosed) return;
    emit(CaseDetailsLoading());
    try {
      final sessions = await repository.getCaseSessions(caseId);
      final notes = await repository.getCaseNotes(caseId);
      final repo = repository;
      final transactions = repo is ScopedAppRepository && !repo.canReadFinance
          ? <TransactionEntity>[]
          : await repo.getCaseTransactions(caseId);
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
      if (!isClosed) {
        emit(CaseDetailsError('تعذر تحميل تفاصيل القضية. حاول مرة أخرى.'));
      }
    }
  }

  Future<bool> _save(String caseId, Future<void> Function() operation) async {
    if (_saving || isClosed) return false;
    _saving = true;
    try {
      await operation();
      await loadCaseDetails(caseId);
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
    }
  }

  Future<bool> addCaseNote(String caseId, String content) => _save(
    caseId,
    () => repository.addCaseNote(caseId: caseId, content: content),
  );

  Future<bool> addCasePayment({
    required String caseId,
    required String clientId,
    required String title,
    required double amount,
  }) => _save(
    caseId,
    () => repository.addTransaction(
      title: title,
      amount: amount,
      type: 'INCOME',
      caseId: caseId,
      clientId: clientId,
    ),
  );

  Future<bool> addDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  }) => _save(
    caseId,
    () => repository.addCaseDocument(
      caseId: caseId,
      title: title,
      filePath: filePath,
      fileType: fileType,
    ),
  );
}
