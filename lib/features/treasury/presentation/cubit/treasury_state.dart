import 'package:equatable/equatable.dart';
import 'package:seneb_law/core/database/database.dart';

abstract class TreasuryState extends Equatable {
  const TreasuryState();

  @override
  List<Object> get props => [];
}

class TreasuryInitial extends TreasuryState {}

class TreasuryLoading extends TreasuryState {}

class TreasuryLoaded extends TreasuryState {
  final List<TransactionEntity> transactions;
  final Map<String, double> summary;

  const TreasuryLoaded({
    required this.transactions,
    required this.summary,
  });

  @override
  List<Object> get props => [transactions, summary];
}

class TreasuryError extends TreasuryState {
  final String message;
  const TreasuryError(this.message);

  @override
  List<Object> get props => [message];
}