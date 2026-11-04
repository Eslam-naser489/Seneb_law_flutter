import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'sessions_state.dart';

class SessionsCubit extends Cubit<SessionsState> {
  final AppRepository repository;

  SessionsCubit(this.repository) : super(SessionsInitial());

  // جلب جلسات اليوم والغد معاً
  Future<void> loadDashboardSessions() async {
    emit(SessionsLoading());
    try {
      final today = await repository.getTodaySessions();
      final tomorrow = await repository.getTomorrowSessions(); // جلب بكرة
      
      emit(SessionsLoaded(
        todaySessions: today,
        tomorrowSessions: tomorrow,
      ));
    } catch (e) {
      emit(SessionsError(e.toString()));
    }
  }

  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
  }) async {
    try {
      await repository.addSession(
        caseId: caseId,
        sessionDate: sessionDate,
        courtLocation: courtLocation,
      );
      // تحديث الشاشة بعد الإضافة
      await loadDashboardSessions();
    } catch (e) {
      emit(SessionsError(e.toString()));
    }
  }
}