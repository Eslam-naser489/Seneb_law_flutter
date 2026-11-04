import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'clients_state.dart';

class ClientsCubit extends Cubit<ClientsState> {
  final AppRepository repository;
  
  // كاش للاحتفاظ بالقائمة الأصلية عشان الفلترة تتم بسرعة بدون الرجوع للداتابيز كل حرف
  List<ClientEntity> _allClients = [];

  ClientsCubit(this.repository) : super(ClientsInitial());

  Future<void> loadClients() async {
    emit(ClientsLoading());
    try {
      _allClients = await repository.getActiveClients();
      emit(ClientsLoaded(_allClients));
    } catch (e) {
      emit(ClientsError(e.toString()));
    }
  }

  // دالة البحث اللحظي
  void searchClients(String query) {
    if (query.trim().isEmpty) {
      emit(ClientsLoaded(_allClients));
    } else {
      final filtered = _allClients.where((c) => 
        c.name.toLowerCase().contains(query.toLowerCase())
      ).toList();
      emit(ClientsLoaded(filtered));
    }
  }

  Future<void> addClient({required String name, String? phone, String? lawyerId}) async {
    try {
      await repository.addClient(name: name, phone: phone, lawyerId: lawyerId);
      await loadClients(); 
    } catch (e) {
      emit(ClientsError(e.toString()));
    }
  }

  Future<void> archiveClient(String id) async {
    try {
      await repository.archiveClient(id);
      await loadClients(); 
    } catch (e) {
      emit(ClientsError(e.toString()));
    }
  }
}