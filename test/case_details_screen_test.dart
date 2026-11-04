import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/cases/presentation/screens/case_details_screen.dart';

class _CaseRepository extends AppRepository {
  _CaseRepository(super.db);

  final transactions = <TransactionEntity>[
    TransactionEntity(
      id: 'income',
      title: 'Fees',
      amount: 100,
      type: 'INCOME',
      transactionDate: DateTime(2026),
    ),
    TransactionEntity(
      id: 'expense',
      title: 'Travel',
      amount: 30,
      type: 'EXPENSE',
      transactionDate: DateTime(2026),
    ),
  ];

  @override
  Future<List<SessionEntity>> getCaseSessions(String caseId) async => [];
  @override
  Future<List<CaseNoteEntity>> getCaseNotes(String caseId) async => [];
  @override
  Future<List<CaseDocumentEntity>> getCaseDocuments(String caseId) async => [];
  @override
  Future<List<TransactionEntity>> getCaseTransactions(String caseId) async =>
      List.of(transactions);

  @override
  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type,
    String? caseId,
    String? clientId,
  }) async {
    transactions.add(
      TransactionEntity(
        id: 'payment',
        title: title,
        amount: amount,
        type: type,
        transactionDate: DateTime(2026),
        caseId: caseId,
        clientId: clientId,
      ),
    );
  }
}

void main() {
  testWidgets(
    'payments exclude expenses and retain the financial tab after saving',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = _CaseRepository(db);
      await tester.pumpWidget(
        RepositoryProvider<AppRepository>.value(
          value: repository,
          child: MaterialApp(
            home: CaseDetailsScreen(
              caseWithClient: CaseWithClient(
                caseEntity: CaseEntity(
                  id: 'case',
                  clientId: 'client',
                  caseNumber: '123',
                  status: 'جارية',
                  createdAt: DateTime(2026),
                ),
                client: ClientEntity(
                  id: 'client',
                  name: 'Client',
                  isArchived: false,
                  createdAt: DateTime(2026),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('الماليات'));
      await tester.tap(find.text('الماليات'));
      await tester.pumpAndSettle();
      expect(find.text('إجمالي المدفوع: 100.0 ج.م'), findsOneWidget);
      expect(find.text('-30.0 ج.م'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('دفعة جديدة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Infinity');
      await tester.tap(find.text('حفظ الدفعة'));
      await tester.pumpAndSettle();
      expect(repository.transactions.length, 2);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '50');
      await tester.tap(find.text('حفظ الدفعة'));
      await tester.pumpAndSettle();
      expect(find.text('إجمالي المدفوع: 150.0 ج.م'), findsOneWidget);
      expect(repository.transactions.length, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
