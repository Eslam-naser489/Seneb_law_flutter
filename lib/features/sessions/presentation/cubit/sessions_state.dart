import 'package:equatable/equatable.dart';
import 'package:seneb_law/core/database/app_repository.dart';

abstract class SessionsState extends Equatable {
  const SessionsState();

  @override
  List<Object> get props => [];
}

class SessionsInitial extends SessionsState {}

class SessionsLoading extends SessionsState {}

class SessionsLoaded extends SessionsState {
  final List<SessionWithDetails> todaySessions;
  final List<SessionWithDetails> tomorrowSessions; // القائمة الجديدة

  const SessionsLoaded({
    required this.todaySessions,
    required this.tomorrowSessions,
  });

  @override
  List<Object> get props => [todaySessions, tomorrowSessions];
}

class SessionsError extends SessionsState {
  final String message;
  const SessionsError(this.message);

  @override
  List<Object> get props => [message];
}