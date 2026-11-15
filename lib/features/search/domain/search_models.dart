class SearchFilter {
  const SearchFilter({
    this.lawyerId,
    this.status,
    this.archive = ArchiveFilter.active,
  });
  final String? lawyerId, status;
  final ArchiveFilter archive;
}

enum ArchiveFilter { active, archived, all }

class SearchHit {
  const SearchHit(
    this.clientId,
    this.name,
    this.archived, {
    this.caseId,
    this.caseNumber,
    this.match,
  });
  final String clientId, name;
  final bool archived;
  final String? caseId, caseNumber, match;
}
