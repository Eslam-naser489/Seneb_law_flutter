import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/search/data/arabic_search.dart';
import 'package:seneb_law/main.dart';

void main() {
  testWidgets(
    'global search debounces typing and opens the correct Client 360 page',
    (tester) async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(setup: registerSearchFunctions),
      );
      final access = OfficeAccess(AppRepository(db));
      late ScopedAppRepository workspace;
      addTearDown(() async {
        access.dispose();
        await db.close();
      });
      await tester.runAsync(() async {
        await access.bootstrapOwner('مالك البحث', '389650');
        final ownerId = (await access.unlockProfiles()).single.id;
        await access.signIn(ownerId, '389650');
        workspace = access.workspace(access.session!);
        await workspace.addClient(name: 'موكل قبل التعديل');
        final id = await workspace.addClient(name: 'أمينة البحث');
        await workspace.addCase(clientId: id, caseNumber: '870/2026');
      });

      await tester.pumpWidget(
        SenebLawApp(repository: workspace, onLock: access.lock),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('البحث الموحد (Ctrl+K)'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, 'موكل قبل');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(field, 'امينه البحث');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('موكل قبل التعديل'), findsNothing);
      expect(find.text('أمينة البحث'), findsOneWidget);

      await tester.tap(find.text('أمينة البحث'));
      await tester.pumpAndSettle();
      expect(find.text('870/2026'), findsOneWidget);
      expect(find.text('البيانات'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
