import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'sessions_state.dart';

class SessionsCubit extends Cubit<SessionsState> {
  final AppRepository repository;

  SessionsCubit(this.repository) : super(SessionsInitial());

  // جلب جلسات اليوم من الـ Repository
  Future<void> loadTodaySessions() async {
    emit(SessionsLoading()); // إظهار علامة التحميل
    try {
      final sessions = await repository.getTodaySessions();
      emit(SessionsLoaded(sessions)); // تمرير البيانات بنجاح للشاشة
    } catch (e) {
      emit(SessionsError(e.toString())); // في حالة حدوث خطأ
    }
  }

  // إضافة جلسة جديدة
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
      
      // بمجرد الحفظ بنجاح، نقوم بجلب جلسات اليوم مرة أخرى لتحديث الشاشة فوراً
      await loadTodaySessions();
    } catch (e) {
      emit(SessionsError(e.toString()));
    }
  }
}