import 'package:seneb_law/core/database/database.dart';
import 'package:uuid/uuid.dart';
import '../domain/lawyers_repository.dart';

class DriftLawyersRepository implements LawyersRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DriftLawyersRepository(this.db);

  @override
  Future<String> addLawyer(String name) async {
    final id = _uuid.v4();

    await db
        .into(db.officeLawyers)
        .insert(OfficeLawyersCompanion.insert(id: id, name: name));

    return id;
  }

  @override
  Future<List<OfficeLawyerEntity>> getLawyers() async {
    return await db.select(db.officeLawyers).get();
  }
}
