import 'package:seneb_law/core/database/database.dart';

abstract interface class LawyersRepository {
  Future<String> addLawyer(String name);

  Future<List<OfficeLawyerEntity>> getLawyers();
}
