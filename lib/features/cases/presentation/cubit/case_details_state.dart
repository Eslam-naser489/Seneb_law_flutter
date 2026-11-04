import 'package:equatable/equatable.dart';
import 'package:seneb_law/core/database/database.dart';

abstract class CaseDetailsState extends Equatable {
  const CaseDetailsState();

  @override
  List<Object> get props => [];
}

class CaseDetailsInitial extends CaseDetailsState {}

class CaseDetailsLoading extends CaseDetailsState {}

class CaseDetailsLoaded extends CaseDetailsState {
  final List<SessionEntity> sessions;
  final List<CaseNoteEntity> notes;
  final List<TransactionEntity> transactions; // الجديد

  const CaseDetailsLoaded({
    required this.sessions,
    required this.notes,
    required this.transactions, // الجديد
  });

  @override
  List<Object> get props => [sessions, notes, transactions];
}

class CaseDetailsError extends CaseDetailsState {
  final String message;
  const CaseDetailsError(this.message);

  @override
  List<Object> get props => [message];
}