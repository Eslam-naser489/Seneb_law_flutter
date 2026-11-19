import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/clients/presentation/cubit/clients_cubit.dart';
import 'package:seneb_law/features/clients/presentation/screens/add_client_screen.dart';
import 'package:seneb_law/features/cases/presentation/screens/case_details_screen.dart';
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_cubit.dart';
import 'package:seneb_law/features/sessions/presentation/screens/add_session_screen.dart';
import 'package:seneb_law/features/shared/presentation/async_save_dialog.dart';
import 'package:seneb_law/features/treasury/presentation/cubit/treasury_cubit.dart';
import 'package:seneb_law/features/treasury/presentation/screens/treasury_screen.dart';

class _FailingClientRepository extends AppRepository {
  _FailingClientRepository(super.db);

  int calls = 0;
  final pending = Completer<String>();

  @override
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) {
    calls++;
    return pending.future;
  }
}

class _SessionRepository extends AppRepository {
  _SessionRepository(super.db);

  String? capturedCourt;
  String? capturedCircle;
  String? capturedDecision;

  @override
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  }) async {
    capturedCourt = courtLocation;
    capturedCircle = circleNumber;
    capturedDecision = decision;
    throw StateError('Injected write failure');
  }
}

void main() {
  testWidgets('save dialog releases controllers after its exit transition', (
    tester,
  ) async {
    var released = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final controller = TextEditingController(text: 'بيانات الاختبار');
                await showAsyncSaveDialog(
                  context: context,
                  builder: (_) => AsyncSaveDialog(
                    title: 'نافذة اختبار الحفظ',
                    content: TextField(controller: controller),
                    validate: () => null,
                    onSave: () async => true,
                  ),
                );
                controller.dispose();
                released = true;
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    expect(released, isFalse);
    await tester.pumpAndSettle();
    expect(released, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production treasury and case history are explicitly read-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = AppRepository(db);
    final client = await repository.addClient(name: 'موكل اختباري');
    await repository.addCase(clientId: client, caseNumber: '123');
    final cubit = TreasuryCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      RepositoryProvider<AppRepository>.value(
        value: repository,
        child: BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: TreasuryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('السجل المالي القديم للعرض فقط.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    final caseItem = (await repository.getCasesWithClients()).single;
    await tester.pumpWidget(
      RepositoryProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(home: CaseDetailsScreen(caseWithClient: caseItem)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('الماليات'));
    await tester.tap(find.text('الماليات'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('السجل المالي القديم للعرض فقط.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'دفعة جديدة'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog blocks duplicate saves and retains inputs on failure', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'ملاحظة محفوظة في المسودة');
    addTearDown(controller.dispose);
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => AsyncSaveDialog(
                  title: 'إضافة ملاحظة',
                  content: TextField(controller: controller),
                  validate: () => null,
                  onSave: () {
                    calls++;
                    return pending.future;
                  },
                ),
              ),
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      )).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'إلغاء'))
          .onPressed,
      isNull,
    );
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(controller.text, 'ملاحظة محفوظة في المسودة');
    expect(
      find.text('تعذر الحفظ. احتُفظ بالبيانات المدخلة، حاول مرة أخرى.'),
      findsOneWidget,
    );
    expect(calls, 1);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets('client form stays open after a pending save fails', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = _FailingClientRepository(db);
    final cubit = ClientsCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      RepositoryProvider<AppRepository>.value(
        value: repository,
        child: BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: AddClientScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'موكل تجريبي');
    await tester.ensureVisible(find.text('حفظ بيانات الموكل'));
    await tester.tap(find.text('حفظ بيانات الموكل'));
    await tester.pump();
    expect(repository.calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending.completeError(StateError('Injected write failure'));
    await tester.pumpAndSettle();
    expect(find.byType(AddClientScreen), findsOneWidget);
    expect(find.text('موكل تجريبي'), findsOneWidget);
    expect(
      find.text('تعذر الحفظ. احتُفظ بالبيانات المدخلة، حاول مرة أخرى.'),
      findsOneWidget,
    );
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session fields propagate separately and survive save failure', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = _SessionRepository(db);
    final clientId = await repository.addClient(name: 'موكل الجلسة');
    await repository.addCase(clientId: clientId, caseNumber: '123/2026');
    final cubit = SessionsCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      RepositoryProvider<AppRepository>.value(
        value: repository,
        child: BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: AddSessionScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('123/2026 - موكل الجلسة').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'محكمة القاهرة');
    await tester.enterText(find.byType(TextFormField).at(1), 'الدائرة 7');
    await tester.enterText(find.byType(TextFormField).at(2), 'تأجيل للمرافعة');
    await tester.ensureVisible(find.text('حفظ الجلسة'));
    await tester.tap(find.text('حفظ الجلسة'));
    await tester.pumpAndSettle();
    expect(repository.capturedCourt, 'محكمة القاهرة');
    expect(repository.capturedCircle, 'الدائرة 7');
    expect(repository.capturedDecision, 'تأجيل للمرافعة');
    expect(find.byType(AddSessionScreen), findsOneWidget);
    expect(find.text('تأجيل للمرافعة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
