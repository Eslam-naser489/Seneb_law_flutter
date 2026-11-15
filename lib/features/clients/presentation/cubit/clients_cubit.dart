import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'clients_state.dart';

class ClientsCubit extends Cubit<ClientsState> {
  final AppRepository repository;
  bool _saving = false;

  // كاش للاحتفاظ بالقائمة الأصلية عشان الفلترة تتم بسرعة بدون الرجوع للداتابيز كل حرف
  List<ClientEntity> _allClients = [];

  ClientsCubit(this.repository) : super(ClientsInitial());

  Future<void> loadClients() async {
    if (!isClosed) emit(ClientsLoading());
    try {
      _allClients = await repository.getActiveClients();
      if (!isClosed) emit(ClientsLoaded(_allClients));
    } catch (e) {
      if (!isClosed) emit(ClientsError('تعذر تحميل الموكلين. حاول مرة أخرى.'));
    }
  }

  // دالة البحث اللحظي
  void searchClients(String query) {
    if (query.trim().isEmpty) {
      if (!isClosed) emit(ClientsLoaded(_allClients));
    } else {
      final filtered = _allClients
          .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
      if (!isClosed) emit(ClientsLoaded(filtered));
    }
  }

  Future<bool> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) async {
    if (_saving || isClosed) return false;
    _saving = true;
    try {
      await repository.addClient(name: name, phone: phone, lawyerId: lawyerId);
      await loadClients();
      return true;
    } catch (e) {
      return false;
    } finally {
      _saving = false;
    }
  }

  Future<void> archiveClient(String id) async {
    try {
      await repository.archiveClient(id);
      await loadClients();
    } catch (e) {
      if (!isClosed) emit(ClientsError('تعذر تحميل الموكلين. حاول مرة أخرى.'));
    }
  }
}
