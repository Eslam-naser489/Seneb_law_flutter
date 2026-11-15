import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/finance/presentation/client_account_screen.dart';

void main() {
  Future<void> settleDatabase(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mobile RTL account keeps invalid input and saves an Arabic-number payment once',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final access = OfficeAccess(AppRepository(db));
      late ScopedAppRepository repo;
      late String client;
      await tester.runAsync(() async {
        await access.bootstrapOwner('مالك اختبار', '481637');
        await access.signIn(
          (await access.unlockProfiles()).single.id,
          '481637',
        );
        repo = access.workspace(access.session!);
        client = await repo.addClient(name: 'موكل اختبار');
      });
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        access.dispose();
        await db.close();
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepositoryProvider<AppRepository>.value(
            value: repo,
            child: MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: ClientAccountScreen(clientId: client),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settleDatabase(tester);
      expect(
        find.text('لا توجد حركات مالية. أضف اتفاق أتعاب أو دفعة.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إضافة حركة'));
      await settleDatabase(tester);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '0');
      await tester.enterText(fields.at(1), 'دفعة تجريبية');
      await tester.runAsync(() async {
        await tester.tap(find.text('حفظ'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settleDatabase(tester);
      expect(find.text('راجع نوع الحركة وقيمة المبلغ.'), findsOneWidget);
      expect(find.text('دفعة تجريبية'), findsOneWidget);
      await tester.enterText(fields.at(0), '١٢٣٫٤٥');
      await tester.runAsync(() async {
        await tester.tap(find.text('حفظ'));
        await tester.tap(find.text('حفظ'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settleDatabase(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final account = await tester.runAsync(() => repo.clientAccount(client));
      expect(account!.entries, hasLength(1));
      expect(account.balance, -12345);
      expect(find.text('رصيد لصالح الموكل: 123.45 ج.م'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
