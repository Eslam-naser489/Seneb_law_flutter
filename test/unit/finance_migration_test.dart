import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import '../drift/generated/app/generated/schema_v3.dart' as v3;

void main() {
  test(
    'populated v3 is backed up before v5 and both snapshots restore without loss',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'seneb-finance-migration-',
      );
      final file = File(p.join(root.path, 'seneb_law_db.sqlite'));
      final old = v3.DatabaseAtV3(NativeDatabase(file));
      AppDatabase? upgraded;
      try {
        await old.customStatement(
          "INSERT INTO office_lawyers(id,name) VALUES ('staff','اصطناعي')",
        );
        await old.customStatement(
          "INSERT INTO clients(id,name) VALUES ('client','موكل اصطناعي')",
        );
        await old.customStatement(
          "INSERT INTO transactions(id,title,amount,type,client_id) VALUES ('old','قديم',1.005,'INCOME','client')",
        );
        await old.customStatement(
          "INSERT INTO legacy_transaction_reviews(id,legacy_transaction_id,source_amount_text,proposed_amount_minor,rounding_residual,has_subcent_precision,is_negative,ownership_mismatch) VALUES ('r','old','1.005',101,'-0.005',1,0,0)",
        );
        await old.close();
        upgraded = AppDatabase.openAt(root);
        expect(
          (await upgraded.select(upgraded.clients).get()).single.id,
          'client',
        );
        expect(
          await upgraded.select(upgraded.clientLedgerEntries).get(),
          isEmpty,
        );
        expect(
          (await upgraded.select(upgraded.transactions).get()).single.amount,
          1.005,
        );
        expect(
          (await upgraded.select(upgraded.legacyTransactionReviews).get())
              .single
              .reviewStatus,
          'PENDING',
        );
        final backups = await Directory(
          p.join(root.path, 'backups'),
        ).list().where((e) => e is Directory).cast<Directory>().toList();
        expect(backups, hasLength(1));
        expect(
          (await BackupService().validate(backups.single))['schemaVersion'],
          3,
        );
        final current = await BackupService().create(
          databaseFile: file,
          storageRoot: root,
          destinationRoot: Directory(p.join(root.path, 'exports')),
        );
        expect(
          (await BackupService().validate(current.directory))['schemaVersion'],
          5,
        );
        final restored = await BackupService().restoreIsolated(
          backup: current.directory,
          destination: Directory(p.join(root.path, 'restored')),
        );
        final native = sqlite.sqlite3.open(
          p.join(restored.path, 'seneb_law_db.sqlite'),
        );
        try {
          expect(native.userVersion, 5);
          expect(
            native
                .select(
                  'SELECT source_amount_text FROM legacy_transaction_reviews',
                )
                .single['source_amount_text'],
            '1.005',
          );
          expect(native.select('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          native.close();
        }
      } finally {
        await upgraded?.close();
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
  );
}
