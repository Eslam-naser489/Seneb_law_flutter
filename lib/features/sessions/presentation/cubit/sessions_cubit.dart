import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'sessions_state.dart';

class SessionsCubit extends Cubit<SessionsState> {
  final AppRepository repository;
  bool _saving = false;

  SessionsCubit(this.repository) : super(SessionsInitial());

  // جلب جلسات اليوم والغد معاً
  Future<void> loadDashboardSessions() async {
    if (!isClosed) emit(SessionsLoading());
    try {
      final today = await repository.getTodaySessions();
      final tomorrow = await repository.getTomorrowSessions(); // جلب بكرة

      if (!isClosed) {
        emit(SessionsLoaded(todaySessions: today, tomorrowSessions: tomorrow));
      }
    } catch (e) {
      if (!isClosed) emit(SessionsError('تعذر تحميل الجلسات. حاول مرة أخرى.'));
    }
  }

  Future<bool> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  }) async {
    if (_saving || isClosed) return false;
    _saving = true;
    try {
      await repository.addSession(
        caseId: caseId,
        sessionDate: sessionDate,
        courtLocation: courtLocation,
        circleNumber: circleNumber,
        decision: decision,
      );
      // تحديث الشاشة بعد الإضافة
      await loadDashboardSessions();
      return true;
    } catch (e) {
      return false;
    } finally {
      _saving = false;
    }
  }
}
