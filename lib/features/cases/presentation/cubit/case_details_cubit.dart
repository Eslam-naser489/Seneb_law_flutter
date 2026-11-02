import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'case_details_state.dart';

class CaseDetailsCubit extends Cubit<CaseDetailsState> {
  final AppRepository repository;

  CaseDetailsCubit(this.repository) : super(CaseDetailsInitial());

  // جلب جلسات وملاحظات القضية معاً
  Future<void> loadCaseDetails(String caseId) async {
    emit(CaseDetailsLoading());
    try {
      final sessions = await repository.getCaseSessions(caseId);
      final notes = await repository.getCaseNotes(caseId);
      emit(CaseDetailsLoaded(sessions: sessions, notes: notes));
    } catch (e) {
      emit(CaseDetailsError(e.toString()));
    }
  }

  // إضافة ملاحظة جديدة للقضية
  Future<void> addCaseNote(String caseId, String content) async {
    try {
      await repository.addCaseNote(caseId: caseId, content: content);
      await loadCaseDetails(caseId); // إعادة التحميل لتحديث الشاشة
    } catch (e) {
      emit(CaseDetailsError(e.toString()));
    }
  }
}