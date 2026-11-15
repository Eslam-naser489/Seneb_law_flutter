import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as native;
import 'package:uuid/uuid.dart';
import '../money/money.dart';
import '../storage/backup_service.dart';
import '../../features/search/data/arabic_search.dart';
import 'database.steps.dart' as historical;

part 'database.g.dart';
part 'sprint_zero_schema.dart';
part 'sprint_zero_migration.dart';
part 'finance_schema.dart';
part 'finance_migration.dart';
part 'report_schema.dart';
part 'report_migration.dart';

@DataClassName('OfficeLawyerEntity')
class OfficeLawyers extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get barRegistrationNumber => text().nullable()();
  TextColumn get role => text().withDefault(const Constant('LAWYER'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get photoDocumentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ClientEntity')
class Clients extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get phoneSecondary => text().nullable()();
  TextColumn get whatsappNumber => text().nullable()();
  TextColumn get nationalId => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get occupation => text().nullable()();
  TextColumn get referralSource => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get whatsappConsentStatus =>
      text().withDefault(const Constant('UNKNOWN'))();
  DateTimeColumn get consentRecordedAt => dateTime().nullable()();
  @ReferenceName('consentClients')
  TextColumn get consentRecordedBy =>
      text().nullable().references(OfficeLawyers, #id)();
  TextColumn get consentSource => text().nullable()();
  TextColumn get assignedLawyerId =>
      text().nullable().references(OfficeLawyers, #id)();
  // حقل الأرشفة (الافتراضي: غير مؤرشف)
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CaseEntity')
class Cases extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get caseNumber => text()();
  TextColumn get opponentName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('جارية'))();
  TextColumn get statusCode => text().withDefault(const Constant('ACTIVE'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SessionEntity')
class Sessions extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)();
  DateTimeColumn get sessionDate => dateTime()();
  TextColumn get courtLocation => text()();
  TextColumn get circleNumber => text().nullable()();
  TextColumn get decision => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CaseNoteEntity')
class CaseNotes extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)();
  TextColumn get content => text()();
  TextColumn get visibility => text().withDefault(const Constant('INTERNAL'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

// 6. جدول المعاملات المالية (الخزينة)
@DataClassName('TransactionEntity')
class Transactions extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title =>
      text()(); // اسم المعاملة (مثال: دفعة أتعاب، أو مصاريف مواصلات)
  RealColumn get amount => real()(); // المبلغ
  TextColumn get type =>
      text()(); // نوعها: 'INCOME' (إيراد) أو 'EXPENSE' (مصروف)
  DateTimeColumn get transactionDate =>
      dateTime().withDefault(currentDateAndTime)();

  // لو المعاملة تخص قضية وموكل معين، هنربطهم هنا (ممكن يبقوا null لو دي مصروفات عامة للمكتب)
  TextColumn get caseId => text().nullable().references(Cases, #id)();
  TextColumn get clientId => text().nullable().references(Clients, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

// 7. جدول مستندات القضايا
@DataClassName('CaseDocumentEntity')
class CaseDocuments extends Table with LifecycleColumns {
  TextColumn get id => text()();
  TextColumn get caseId => text().references(Cases, #id)();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()();
  TextColumn get sourceFilePath => text().nullable()();
  TextColumn get storageStatus =>
      text().withDefault(const Constant('LEGACY'))();
  TextColumn get checksum => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get uploadedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    OfficeLawyers,
    Clients,
    Cases,
    Sessions,
    CaseNotes,
    Transactions,
    CaseDocuments,
    ClientLawyers,
    CaseLawyers,
    LocalCredentials,
    AuditLog,
    AppSettings,
    LegacyTransactionReviews,
    ClientLedgerEntries,
    FeeAgreements,
    Installments,
    PaymentAllocations,
    OfficeExpenses,
    FinancialReceipts,
    LegacyClassifications,
    ReportTemplates,
    CaseReports,
    GeneratedDocuments,
    ShareAttempts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());
  AppDatabase.openAt(Directory root, {this.migrationProbe})
    : super(_openAt(root));
  Future<void> Function()? migrationProbe;

  // Constructor مخصص للـ Testing
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await installSprintZeroGuards(this);
        await installFinanceGuards(this);
        await installReportGuards(this);
      },
      onUpgrade: (m, from, to) => transaction(() async {
        if (from < 2) {
          throw UnsupportedError('يجب ترقية قاعدة البيانات إلى v2 أولًا.');
        }
        if (from < 3) await upgradeToThree(this, m);
        if (from < 4) await upgradeToFour(this, m);
        if (from < 5) await upgradeToFive(this, m);
      }),
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS search_notes_by_case '
          'ON case_notes(case_id) WHERE deleted_at IS NULL',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS search_cases_by_client '
          'ON cases(client_id) WHERE deleted_at IS NULL',
        );
        if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw StateError('تعذر فتح القاعدة بسبب روابط بيانات غير سليمة.');
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return _safeLazy(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return _preparedConnection(Directory(p.join(dbFolder.path, 'seneb_law')));
  });
}

LazyDatabase _openAt(Directory root) =>
    _safeLazy(() => _preparedConnection(root));

class _OpeningState {
  bool failed = false;
}

LazyDatabase _safeLazy(Future<QueryExecutor> Function() opener) {
  final state = _OpeningState();
  return _RecoverableLazyDatabase(() async {
    try {
      return await opener();
    } catch (_) {
      state.failed = true;
      rethrow;
    }
  }, state);
}

class _RecoverableLazyDatabase extends LazyDatabase {
  final _OpeningState state;
  _RecoverableLazyDatabase(super.opener, this.state);
  @override
  Future<void> close() async {
    try {
      await super.close();
    } catch (_) {
      // فشل التهيئة قبل إنشاء أي اتصال: لا يوجد مورد مفتوح لإغلاقه.
      if (!state.failed) rethrow;
    }
  }
}

Future<QueryExecutor> _preparedConnection(Directory root) async {
  await root.create(recursive: true);
  final file = File(p.join(root.path, 'seneb_law_db.sqlite'));
  if (await file.exists()) {
    final source = native.sqlite3.open(
      file.path,
      mode: native.OpenMode.readOnly,
    );
    late int version;
    try {
      version = source.userVersion;
    } finally {
      source.close();
    }
    if (version > 0 && version < 5) {
      final backup = await BackupService().create(
        databaseFile: file,
        storageRoot: root,
        destinationRoot: Directory(p.join(root.path, 'backups')),
      );
      if (!backup.isComplete) {
        throw StateError(
          'تعذر بدء الترحيل: توجد مستندات مفقودة. '
          'تم حفظ القاعدة والملفات المتاحة؛ أصلح الملفات أولًا.',
        );
      }
    }
  }
  return NativeDatabase.createInBackground(
    file,
    setup: registerSearchFunctions,
  );
}
