import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'clients_state.dart';

class ClientsCubit extends Cubit<ClientsState> {
  final AppRepository repository;

  ClientsCubit(this.repository) : super(ClientsInitial());

  Future<void> loadClients() async {
    emit(ClientsLoading());
    try {
      final clients = await repository.getActiveClients();
      emit(ClientsLoaded(clients));
    } catch (e) {
      emit(ClientsError(e.toString()));
    }
  }

  // تعديل: أضفنا lawyerId عشان نقدر نربط الموكل بمحامي من الشاشة
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