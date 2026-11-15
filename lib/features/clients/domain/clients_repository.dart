import 'package:seneb_law/core/database/database.dart';

abstract interface class ClientsRepository {
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  });

  Future<void> updateClient(
    String id, {
    String? name,
    String? phone,
    String? lawyerId,
  });

  Future<void> archiveClient(String id);

  Future<List<ClientEntity>> getActiveClients();
}
