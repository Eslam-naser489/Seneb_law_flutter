import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/search/domain/search_models.dart';

void main() {
  test(
    'measures scoped SQL search on a synthetic office-sized Windows fixture',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'seneb-search-fixture-',
      );
      final db = AppDatabase.openAt(root);
      final access = OfficeAccess(AppRepository(db, storageRoot: root));
      try {
        const clients = 500, cases = 1500, notes = 3000;
        await db.batch((batch) {
          batch.insertAll(
            db.clients,
            List.generate(
              clients,
              (i) => ClientsCompanion.insert(
                id: 'u$i',
                name: 'موكل تجريبي رقم $i',
                phone: Value('0100000${i.toString().padLeft(4, '0')}'),
              ),
            ),
          );
          batch.insertAll(
            db.cases,
            List.generate(
              cases,
              (i) => CasesCompanion.insert(
                id: 'c$i',
                clientId: 'u${i % clients}',
                caseNumber: '$i/2026',
                opponentName: Value('خصم تجريبي رقم $i'),
              ),
            ),
          );
          batch.insertAll(
            db.caseNotes,
            List.generate(
              notes,
              (i) => CaseNotesCompanion.insert(
                id: 'n$i',
                caseId: 'c${i % cases}',
                content: 'مُذَكِّرة  متابعة اصطناعية رقم $i',
              ),
            ),
          );
        });
        await access.bootstrapOwner('مالك اختبار القياس', '719346');
        final id = (await access.unlockProfiles()).single.id;
        await access.signIn(id, '719346');
        final workspace = access.workspace(access.session!);
        final queries = [
          ('150/2026', 'c150'),
          ('مذكره متابعة اصطناعيه رقم 2999', 'c1499'),
          ('01000000273', null),
          ('موكل تجريبي رقم 449', null),
        ];
        for (final (query, _) in queries) {
          await workspace.search(query, const SearchFilter());
        }
        final timings = <int>[];
        for (var i = 0; i < 24; i++) {
          final (query, expectedCase) = queries[i % queries.length];
          final timer = Stopwatch()..start();
          final result = await workspace.search(query, const SearchFilter());
          timings.add(timer.elapsedMicroseconds);
          expect(result, isNotEmpty);
          if (expectedCase != null) expect(result.first.caseId, expectedCase);
        }
        timings.sort();
        final p95 = timings[(timings.length * .95).ceil() - 1] / 1000;
        debugPrint(
          'Search fixture: $clients clients, $cases cases, $notes notes, '
          '${timings.length} queries; p95 ${p95.toStringAsFixed(1)} ms.',
        );
      } finally {
        access.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
