import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'cases_state.dart';

class CasesCubit extends Cubit<CasesState> {
  final AppRepository repository;
  
  List<CaseWithClient> _allCases = []; // كاش القضايا

  CasesCubit(this.repository) : super(CasesInitial());

  Future<void> loadCases() async {
    emit(CasesLoading());
    try {
      _allCases = await repository.getCasesWithClients();
      emit(CasesLoaded(_allCases));
    } catch (e) {
      emit(CasesError(e.toString()));
    }
  }

  // دالة البحث: بتبحث في رقم القضية أو في اسم الموكل
  void searchCases(String query) {
    if (query.trim().isEmpty) {
      emit(CasesLoaded(_allCases));
    } else {
      final q = query.toLowerCase();
      final filtered = _allCases.where((c) => 
        c.caseEntity.caseNumber.toLowerCase().contains(q) ||
        c.client.name.toLowerCase().contains(q)
      ).toList();
      emit(CasesLoaded(filtered));
    }
  }

  Future<void> addCase({required String clientId, required String caseNumber, String? opponentName}) async {
    try {
      await repository.addCase(
        clientId: clientId,
        caseNumber: caseNumber,
        opponentName: opponentName,
      );
      await loadCases();
    } catch (e) {
      emit(CasesError(e.toString()));
    }
  }
}