import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/storage/backup_service.dart';
import '../domain/documents_repository.dart';

class DriftDocumentsRepository implements DocumentsRepository {
  final AppDatabase db;
  final Future<Directory> Function() storageRoot;
  DriftDocumentsRepository(this.db, this.storageRoot);

  @override
  Future<void> addCaseDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('أدخل اسم المستند.');
    final prior =
        await (db.select(db.caseDocuments)..where(
              (t) =>
                  t.caseId.equals(caseId) &
                  t.sourceFilePath.equals(filePath) &
                  t.title.equals(title.trim()) &
                  t.deletedAt.isNull(),
            ))
            .get();
    if (prior.isNotEmpty) {
      await _complete(prior.first);
      return;
    }
    final source = File(filePath);
    if (!await source.exists()) {
      throw const FileSystemException('الملف غير متاح.');
    }
    final expectedHash = await BackupService.hashFile(source);
    final id = const Uuid().v4();
    final extension = p.extension(filePath).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)
        ? extension
        : '';
    await db
        .into(db.caseDocuments)
        .insert(
          CaseDocumentsCompanion.insert(
            id: id,
            caseId: caseId,
            title: title.trim(),
            fileType: fileType,
            filePath: 'documents/$id$safeExtension',
            sourceFilePath: Value(filePath),
            checksum: Value(expectedHash),
            fileSize: Value(await source.length()),
            storageStatus: const Value('PENDING'),
          ),
        );
    final row = await (db.select(
      db.caseDocuments,
    )..where((t) => t.id.equals(id))).getSingle();
    await _complete(row);
  }

  @override
  Future<void> resumeImports() async {
    final rows =
        await (db.select(db.caseDocuments)..where(
              (t) =>
                  t.deletedAt.isNull() & t.storageStatus.isNotIn(['AVAILABLE']),
            ))
            .get();
    for (final row in rows) {
      try {
        await _complete(row);
      } on FileSystemException {
        await (db.update(
          db.caseDocuments,
        )..where((t) => t.id.equals(row.id))).write(
          const CaseDocumentsCompanion(storageStatus: Value('MISSING')),
        );
      }
    }
  }

  Future<void> _complete(CaseDocumentEntity row) async {
    final root = await storageRoot();
    await root.create(recursive: true);
    final relative = p.isAbsolute(row.filePath)
        ? 'documents/${row.id}${_extension(row.filePath)}'
        : row.filePath;
    final destination = File(BackupService.safePath(root, relative));
    if (await destination.exists()) {
      final checksum = await BackupService.hashFile(destination);
      if (row.checksum != null && row.checksum == checksum) {
        if (row.storageStatus != 'AVAILABLE') {
          await _markAvailable(row, relative, destination, checksum);
        }
        return;
      }
    }
    final sourcePath = row.sourceFilePath ?? row.filePath;
    final source = File(
      p.isAbsolute(sourcePath)
          ? sourcePath
          : BackupService.safePath(root, sourcePath),
    );
    if (!await source.exists()) {
      throw const FileSystemException('الملف الأصلي غير متاح.');
    }
    final sourceHash = await BackupService.hashFile(source);
    if (row.checksum != null && row.checksum != sourceHash) {
      throw const FileSystemException(
        'تغير الملف الأصلي؛ راجع المستند قبل إعادة الاستيراد.',
      );
    }
    await (db.update(
      db.caseDocuments,
    )..where((t) => t.id.equals(row.id))).write(
      CaseDocumentsCompanion(
        storageStatus: const Value('PENDING'),
        checksum: Value(sourceHash),
        fileSize: Value(await source.length()),
      ),
    );
    await destination.parent.create(recursive: true);
    final staged = File('${destination.path}.part');
    await source.copy(staged.path);
    final checksum = await BackupService.hashFile(staged);
    if (checksum != sourceHash ||
        (row.checksum != null && checksum != row.checksum) ||
        await BackupService.hashFile(source) != checksum) {
      throw const FileSystemException('تغير الملف أثناء النسخ.');
    }
    if (await destination.exists()) await destination.delete();
    await staged.rename(destination.path);
    await _markAvailable(row, relative, destination, checksum);
  }

  Future<void> _markAvailable(
    CaseDocumentEntity row,
    String relative,
    File destination,
    String checksum,
  ) async {
    await (db.update(
      db.caseDocuments,
    )..where((t) => t.id.equals(row.id))).write(
      CaseDocumentsCompanion(
        filePath: Value(relative),
        sourceFilePath: Value(row.sourceFilePath ?? row.filePath),
        storageStatus: const Value('AVAILABLE'),
        checksum: Value(checksum),
        fileSize: Value(await destination.length()),
        updatedAt: Value(DateTime.now().toUtc()),
        revision: Value(row.revision + 1),
      ),
    );
  }

  String _extension(String path) {
    final ext = p.extension(path).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(ext) ? ext : '';
  }

  @override
  Future<List<CaseDocumentEntity>> getCaseDocuments(String caseId) =>
      (db.select(db.caseDocuments)
            ..where((t) => t.caseId.equals(caseId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.uploadedAt)]))
          .get();

  @override
  Future<void> deleteCaseDocument(String id) async {
    final old = await (db.select(
      db.caseDocuments,
    )..where((t) => t.id.equals(id))).getSingle();
    await (db.update(db.caseDocuments)..where((t) => t.id.equals(id))).write(
      CaseDocumentsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
        revision: Value(old.revision + 1),
      ),
    );
  }

  @override
  Future<String> resolveDocumentPath(String storedPath) async {
    final root = await storageRoot();
    final file = File(
      p.isAbsolute(storedPath)
          ? storedPath
          : BackupService.safePath(root, storedPath),
    );
    if (!await file.exists()) {
      throw const FileSystemException('الملف غير متاح.');
    }
    return file.path;
  }
}
