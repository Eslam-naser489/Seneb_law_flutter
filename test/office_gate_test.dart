import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/lawyers/domain/office_models.dart';
import 'package:seneb_law/features/lawyers/presentation/office_gate.dart';

void main() {
  testWidgets(
    'staff switching and idle locking remove the previous workspace and its draft',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final access = OfficeAccess(AppRepository(db));
      late String ownerId;
      late String employeeId;
      addTearDown(() async {
        access.dispose();
        await db.close();
      });

      await tester.runAsync(() async {
        await access.bootstrapOwner('مالك تجريبي', '715382');
        ownerId = (await access.unlockProfiles()).single.id;
        await access.signIn(ownerId, '715382');
        employeeId = await access
            .workspace(access.session!)
            .saveStaff(
              const StaffInput(name: 'موظف تجريبي', role: OfficeRole.lawyer),
              initialPin: '863407',
            );
        await access.signIn(employeeId, '863407');
        await access.changeTemporaryPin(access.session!, '549826');
      });

      await tester.pumpWidget(
        OfficeGate(
          access: access,
          idleTimeout: const Duration(seconds: 10),
          workspace: (repo) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Text('workspace ${repo.staff.id}'),
                  const TextField(key: Key('private-draft')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('فتح البرنامج'), findsWidgets);

      await tester.runAsync(() => access.signIn(ownerId, '715382'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('private-draft')),
        'private synthetic draft',
      );
      expect(find.text('private synthetic draft'), findsOneWidget);

      access.lock();
      await tester.pumpAndSettle();
      expect(find.text('private synthetic draft'), findsNothing);
      expect(find.text('workspace $ownerId'), findsNothing);

      await tester.runAsync(() => access.signIn(employeeId, '549826'));
      await tester.pumpAndSettle();
      expect(find.text('workspace $employeeId'), findsOneWidget);
      expect(find.text('private synthetic draft'), findsNothing);

      await tester.tap(find.byKey(const Key('private-draft')));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(access.session, isNull);
      expect(find.text('workspace $employeeId'), findsNothing);
      expect(find.text('فتح البرنامج'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
