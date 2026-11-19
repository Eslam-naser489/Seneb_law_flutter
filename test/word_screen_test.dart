import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/app/theme/app_theme.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/templates/presentation/word_screens.dart';
import 'support/word_fixture.dart';

void main() {
  testWidgets(
    'RTL Word form retains values on missing field and invalidates review after edits',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final access = OfficeAccess(AppRepository(db));
      late ScopedAppRepository repo;
      late String client, template;
      await tester.runAsync(() async {
        await access.bootstrapOwner('اختبار', '481637');
        await access.signIn(
          (await access.unlockProfiles()).single.id,
          '481637',
        );
        repo = access.workspace(access.session!);
        client = await repo.addClient(name: 'موكل اصطناعي');
        template = await repo.importWordTemplate(
          'اختبار',
          'عقود',
          wordFixture(),
        );
      });
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
              theme: AppTheme.lightTheme,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: WordGenerateScreen(templateId: template, clientId: client),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'اسم الموكل');
      await tester.enterText(field, 'اسم للمستند');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('أكمل الحقل المطلوب'), findsOneWidget);
      expect((tester.widget<TextField>(field)).controller!.text, 'اسم للمستند');
      expect(await tester.runAsync(() => repo.wordDocuments(client)), isEmpty);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'اسم معدل');
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
