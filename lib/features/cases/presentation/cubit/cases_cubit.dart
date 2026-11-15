import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'cases_state.dart';

class CasesCubit extends Cubit<CasesState> {
  final AppRepository repository;
  bool _saving = false;

  List<CaseWithClient> _allCases = []; // كاش القضايا

  CasesCubit(this.repository) : super(CasesInitial());

  bool _mine = false;

  Future<void> loadCases({bool? mine}) async {
    if (mine != null) _mine = mine;
    if (!isClosed) emit(CasesLoading());
    try {
      final repo = repository;
      _allCases = _mine && repo is ScopedAppRepository
          ? await repo.myCases()
          : await repo.getCasesWithClients();
      if (!isClosed) emit(CasesLoaded(_allCases));
    } catch (e) {
      if (!isClosed) emit(CasesError('تعذر تحميل القضايا. حاول مرة أخرى.'));
    }
  }

  // دالة البحث: بتبحث في رقم القضية أو في اسم الموكل
  void searchCases(String query) {
    if (query.trim().isEmpty) {
      if (!isClosed) emit(CasesLoaded(_allCases));
    } else {
      final q = query.toLowerCase();
      final filtered = _allCases
          .where(
            (c) =>
                c.caseEntity.caseNumber.toLowerCase().contains(q) ||
                c.client.name.toLowerCase().contains(q),
          )
          .toList();
      if (!isClosed) emit(CasesLoaded(filtered));
    }
  }

  Future<bool> addCase({
    required String clientId,
    required String caseNumber,
    String? opponentName,
  }) async {
    if (_saving || isClosed) return false;
    _saving = true;
    try {
      await repository.addCase(
        clientId: clientId,
        caseNumber: caseNumber,
        opponentName: opponentName,
      );
      await loadCases();
      return true;
    } catch (e) {
      return false;
    } finally {
      _saving = false;
    }
  }
}
