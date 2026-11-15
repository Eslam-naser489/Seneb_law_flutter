import 'package:seneb_law/core/database/database.dart';

abstract interface class DocumentsRepository {
  Future<void> resumeImports();
  Future<String> resolveDocumentPath(String storedPath);
  Future<void> addCaseDocument({
    required String caseId,
    required String title,
    required String filePath,
    required String fileType,
  });

  Future<List<CaseDocumentEntity>> getCaseDocuments(String caseId);

  Future<void> deleteCaseDocument(String id);
}
