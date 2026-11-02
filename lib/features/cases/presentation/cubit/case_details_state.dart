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

  const CaseDetailsLoaded({
    required this.sessions,
    required this.notes,
  });

  @override
  List<Object> get props => [sessions, notes];
}

class CaseDetailsError extends CaseDetailsState {
  final String message;
  const CaseDetailsError(this.message);

  @override
  List<Object> get props => [message];
}