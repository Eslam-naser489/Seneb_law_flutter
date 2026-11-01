import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'cases_state.dart';

class CasesCubit extends Cubit<CasesState> {
  final AppRepository repository;

  CasesCubit(this.repository) : super(CasesInitial());

  Future<void> loadCases() async {
    emit(CasesLoading());
    try {
      final casesList = await repository.getCasesWithClients();
      emit(CasesLoaded(casesList));
    } catch (e) {
      emit(CasesError(e.toString()));
    }
  }

  Future<void> addCase({required String clientId, required String caseNumber, String? opponentName}) async {
    try {
      await repository.addCase(
        clientId: clientId,
        caseNumber: caseNumber,
        opponentName: opponentName,
      );
      await loadCases(); // تحديث القائمة بعد الإضافة
    } catch (e) {
      emit(CasesError(e.toString()));
    }
  }
}