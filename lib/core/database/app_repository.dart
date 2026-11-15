import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../security/pin_hasher.dart';
import '../../features/lawyers/domain/office_models.dart';
import '../../features/clients/domain/client_profile.dart';
import '../../features/search/domain/search_models.dart';
import '../../features/search/data/arabic_search.dart';
import 'audit_writer.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:seneb_law/features/lawyers/domain/lawyers_repository.dart';
import 'package:seneb_law/features/lawyers/data/drift_lawyers_repository.dart';
import 'package:seneb_law/features/clients/domain/clients_repository.dart';
import 'package:seneb_law/features/clients/data/drift_clients_repository.dart';
import 'package:seneb_law/features/cases/domain/cases_repository.dart';
import 'package:seneb_law/features/cases/data/drift_cases_repository.dart';
import 'package:seneb_law/features/sessions/domain/sessions_repository.dart';
import 'package:seneb_law/features/sessions/data/drift_sessions_repository.dart';
import 'package:seneb_law/features/notes/domain/notes_repository.dart';
import 'package:seneb_law/features/notes/data/drift_notes_repository.dart';
import 'package:seneb_law/features/treasury/domain/treasury_repository.dart';
import 'package:seneb_law/features/treasury/data/drift_treasury_repository.dart';
import 'package:seneb_law/features/documents/domain/documents_repository.dart';
import 'package:seneb_law/features/documents/data/drift_documents_repository.dart';

import '../storage/backup_service.dart';
import '../storage/write_coordinator.dart';
import 'database.dart';
import 'models.dart';
import '../money/money.dart';
import '../../features/finance/domain/finance_models.dart';
import '../../features/reports/domain/report_models.dart';

export 'models.dart';
part 'office_access.dart';
part 'scoped_repository.dart';
part 'workspace_queries.dart';
part 'search_queries.dart';
part 'finance_queries.dart';
part 'report_queries.dart';

/// واجهة انتقالية تحافظ على الشاشات الحالية أثناء فصل المستودعات.
class AppRepository {
  final AppDatabase _db;
  final Directory? storageRoot;
  final _writes = WriteCoordinator();
  late final LawyersRepository lawyersRepository = DriftLawyersRepository(_db);
  late final ClientsRepository clientsRepository = DriftClientsRepository(_db);
  late final CasesRepository casesRepository = DriftCasesRepository(_db);
  late final SessionsRepository sessionsRepository = DriftSessionsRepository(
    _db,
  );
  late final NotesRepository notesRepository = DriftNotesRepository(_db);
  late final TreasuryRepository treasuryRepository = DriftTreasuryRepository(
    _db,
  );
  late final DocumentsRepository documentsRepository = DriftDocumentsRepository(
    _db,
    _resolveStorageRoot,
  );

  AppRepository(this._db, {this.storageRoot});
  bool get canPostLegacyTransactions => false;

  Future<Directory> _resolveStorageRoot() async =>
      storageRoot ??
      Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'seneb_law'),
      );

  Future<void> initialize() => _writes.run(() async {
    await _db.customSelect('SELECT 1').get();
    await documentsRepository.resumeImports();
  });

  Future<BackupResult> createBackup(Directory destinationRoot) =>
      _writes.run(() async {
        await _db.customSelect('SELECT 1').get();
        await documentsRepository.resumeImports();
        final root = await _resolveStorageRoot();
        return BackupService().create(
          databaseFile: File(p.join(root.path, 'seneb_law_db.sqlite')),
          storageRoot: root,
          destinationRoot: destinationRoot,
        );
      });

  Future<String> addLawyer(String name) =>
      _writes.run(() => lawyersRepository.addLawyer(name));
  Future<List<OfficeLawyerEntity>> getLawyers() =>
      lawyersRepository.getLawyers();
  Future<String> addClient({
    required String name,
    String? phone,
    String? lawyerId,
  }) => _writes.run(
    () => clientsRepository.addClient(
      name: name,
      phone: phone,
      lawyerId: lawyerId,
    ),
  );
  Future<void> updateClient(
    String id, {
    String? name,
    String? phone,
    String? lawyerId,
  }) => _writes.run(
    () => clientsRepository.updateClient(
      id,
      name: name,
      phone: phone,
      lawyerId: lawyerId,
    ),
  );
  Future<void> archiveClient(String id) =>
      _writes.run(() => clientsRepository.archiveClient(id));
  Future<List<ClientEntity>> getActiveClients() =>
      clientsRepository.getActiveClients();
  Future<String> addCase({
    required String clientId,
    required String caseNumber,
    String? opponentName,
  }) => _writes.run(
    () => casesRepository.addCase(
      clientId: clientId,
      caseNumber: caseNumber,
      opponentName: opponentName,
    ),
  );
  Future<List<CaseWithClient>> getCasesWithClients() =>
      casesRepository.getCasesWithClients();
  Future<void> updateCaseStatus(
    String caseId,
    String statusCode, {
    required String reason,
  }) => _writes.run(
    () => casesRepository.updateCaseStatus(caseId, statusCode, reason: reason),
  );
  Future<void> addSession({
    required String caseId,
    required DateTime sessionDate,
    required String courtLocation,
    String? circleNumber,
    String? decision,
  }) => _writes.run(
    () => sessionsRepository.addSession(
      caseId: caseId,
      sessionDate: sessionDate,
      courtLocation: courtLocation,
      circleNumber: circleNumber,
      decision: decision,
    ),
  );
  Future<void> updateSessionDecision(
    String sessionId,
    String? decision, {
    required String reason,
  }) => _writes.run(
    () => sessionsRepository.updateSessionDecision(
      sessionId,
      decision,
      reason: reason,
    ),
  );
  Future<List<SessionWithDetails>> getTodaySessions() =>
      sessionsRepository.getTodaySessions();
  Future<List<SessionWithDetails>> getTomorrowSessions() =>
      sessionsRepository.getTomorrowSessions();
  Future<List<SessionEntity>> getCaseSessions(String caseId) =>
      sessionsRepository.getCaseSessions(caseId);
  Future<void> addCaseNote({required String caseId, required String content}) =>
      _writes.run(
        () => notesRepository.addCaseNote(caseId: caseId, content: content),
      );
  Future<List<CaseNoteEntity>> getCaseNotes(String caseId) =>
      notesRepository.getCaseNotes(caseId);
  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type,
    String? caseId,
    String? clientId,
  }) => _writes.run(
    () => treasuryRepository.addTransaction(
      title: title,
      amount: amount,
      type: type,
      caseId: caseId,
      clientId: clientId,
    ),
  );
  Future<List<TransactionEntity>> getAllTransactions() =>
      treasuryRepository.getAllTransactions();
  Future<Map<String, double>> getTreasurySummary() =>
      treasuryRepository.getTreasurySummary();
  Future<List<TransactionEntity>> getCaseTransactions(String caseId) =>
      treasuryRepository.getCaseTransactions(caseId);
  Future<void> addCaseDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  }) => _writes.run(
    () => documentsRepository.addCaseDocument(
      caseId: caseId,
      title: title,
      filePath: filePath,
      fileType: fileType,
    ),
  );
  Future<List<CaseDocumentEntity>> getCaseDocuments(String caseId) =>
      documentsRepository.getCaseDocuments(caseId);
  Future<void> deleteCaseDocument(String id) =>
      _writes.run(() => documentsRepository.deleteCaseDocument(id));
  Future<String> resolveDocumentPath(String storedPath) =>
      documentsRepository.resolveDocumentPath(storedPath);
}
