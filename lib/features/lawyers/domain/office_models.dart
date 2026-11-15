import '../../../core/database/database.dart';

enum OfficeRole {
  owner('OWNER', 'مالك المكتب'),
  partner('PARTNER', 'شريك'),
  lawyer('LAWYER', 'محامٍ'),
  trainee('TRAINEE', 'متدرب'),
  secretary('SECRETARY', 'سكرتارية');

  final String code;
  final String label;
  const OfficeRole(this.code, this.label);

  static OfficeRole parse(String code) =>
      values.firstWhere((role) => role.code == code);
}

class StaffProfile {
  const StaffProfile(
    this.person, {
    required this.hasPin,
    this.mustChangePin = false,
    this.photo,
  });
  final OfficeLawyerEntity person;
  final bool hasPin;
  final bool mustChangePin;
  final List<int>? photo;
}

class UnlockProfile {
  const UnlockProfile(this.id, this.name, this.hasPin);
  final String id, name;
  final bool hasPin;
}

class OfficeFailure implements Exception {
  const OfficeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class StaffInput {
  const StaffInput({
    required this.name,
    required this.role,
    this.phone,
    this.email,
    this.barNumber,
  });
  final String name;
  final OfficeRole role;
  final String? phone;
  final String? email;
  final String? barNumber;
}

class AssignmentView {
  const AssignmentView({
    required this.id,
    required this.lawyerId,
    required this.name,
    required this.role,
    this.startedAt,
    this.endedAt,
    this.reason,
  });
  final String id, lawyerId, name, role;
  final DateTime? startedAt, endedAt;
  final String? reason;
}
