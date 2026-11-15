part of 'app_repository.dart';

extension SearchQueries on ScopedAppRepository {
  Future<List<SearchHit>> search(
    String input,
    SearchFilter filter,
  ) => _read(() async {
    final normalized = normalizeArabic(input);
    if (normalized.isEmpty || normalized.length > 120) return [];
    final args = <Variable>[];
    String bind(String value) {
      args.add(Variable<String>(value));
      return '?${args.length}';
    }

    final tokens = normalized.split(' ').take(12).map(bind).toList();
    String text(String column) => tokens
        .map((token) => 'instr(office_normalize($column), $token) > 0')
        .join(' AND ');
    final fullName = bind(normalized);
    final phoneQuery = RegExp(r'^[+0-9 .()-]+$').hasMatch(normalized)
        ? normalizeEgyptianPhone(normalized)
        : '';
    final numeric = phoneQuery.isNotEmpty && phoneQuery.length >= 3
        ? bind(phoneQuery)
        : null;
    final actor = isOwner ? null : bind(staff.id);

    String clientLink(String who, String client) =>
        'EXISTS (SELECT 1 FROM client_lawyers cl WHERE cl.client_id=$client '
        'AND cl.lawyer_id=$who AND cl.ended_at IS NULL AND cl.deleted_at IS NULL)';
    String caseLink(String who, String caseId) =>
        'EXISTS (SELECT 1 FROM case_lawyers al WHERE al.case_id=$caseId '
        'AND al.lawyer_id=$who AND al.ended_at IS NULL AND al.deleted_at IS NULL)';

    final fullScope = actor == null ? '1' : clientLink(actor, 'u.id');
    final caseScope = actor == null
        ? '1'
        : '($fullScope OR ${caseLink(actor, 'c.id')})';
    final lawyer = filter.lawyerId == null ? null : bind(filter.lawyerId!);
    final lawyerClient = lawyer == null ? '1' : clientLink(lawyer, 'u.id');
    final lawyerCase = lawyer == null
        ? '1'
        : '($lawyerClient OR ${caseLink(lawyer, 'c.id')})';
    final status = filter.status == null
        ? '1'
        : 'c.status_code=${bind(filter.status!)}';
    final archive = switch (filter.archive) {
      ArchiveFilter.active => 'u.is_archived=0',
      ArchiveFilter.archived => 'u.is_archived=1',
      ArchiveFilter.all => '1',
    };
    final phoneMatch = numeric == null
        ? '0'
        : '(instr(office_phone(u.phone), $numeric)>0 OR '
              'instr(office_phone(u.phone_secondary), $numeric)>0 OR '
              'instr(office_phone(u.whatsapp_number), $numeric)>0)';
    final idMatch = numeric == null
        ? '0'
        : 'instr(office_digits(u.national_id), $numeric)>0';
    final exactId = numeric == null
        ? '0'
        : 'office_digits(u.national_id)=$numeric';
    final exactPhone = numeric == null
        ? '0'
        : '(office_phone(u.phone)=$numeric OR office_phone(u.phone_secondary)=$numeric '
              'OR office_phone(u.whatsapp_number)=$numeric)';
    final exactCase = 'office_normalize(c.case_number)=$fullName';
    final caseNumber = text('c.case_number');
    final opponent = text('c.opponent_name');
    final caseNote =
        'EXISTS (SELECT 1 FROM case_notes n WHERE n.case_id=c.id '
        'AND n.deleted_at IS NULL AND (${text('n.content')}))';
    final clientNote = text('u.notes');
    final name = text('u.name');
    final scopedName = '(NOT ($fullScope) AND ($name))';
    final related =
        'EXISTS (SELECT 1 FROM eligible_cases ec WHERE ec.client_id=u.id)';
    final clientFilter = filter.status != null
        ? related
        : (lawyer == null ? '1' : '($lawyerClient OR $related)');

    final rows = await _db.customSelect('''
      WITH eligible_cases AS (
        SELECT c.id, c.client_id, c.case_number, c.opponent_name
        FROM cases c JOIN clients u ON u.id=c.client_id
        WHERE c.deleted_at IS NULL AND u.deleted_at IS NULL AND $archive
          AND $caseScope AND $lawyerCase AND $status
      ), hits AS (
        SELECT u.id AS client_id, u.name, u.is_archived, NULL AS case_id, NULL AS case_number,
          CASE WHEN $idMatch THEN 'ID' WHEN $phoneMatch THEN 'PHONE'
               WHEN ($name) THEN 'NAME' ELSE 'NOTE' END AS match_type,
          CASE WHEN $exactId OR $exactPhone THEN 0 WHEN office_normalize(u.name)=$fullName THEN 1
               WHEN instr(office_normalize(u.name), $fullName)=1 THEN 2 ELSE 3 END AS rank
        FROM clients u WHERE u.deleted_at IS NULL AND $archive AND $fullScope AND $clientFilter
          AND (($name) OR $phoneMatch OR $idMatch OR ($clientNote))
        UNION ALL
        SELECT u.id, u.name, u.is_archived, c.id, c.case_number,
          CASE WHEN ($caseNumber) THEN 'CASE' WHEN ($opponent) THEN 'OPPONENT'
               WHEN $scopedName THEN 'NAME' ELSE 'NOTE' END,
          CASE WHEN $exactCase THEN 0 WHEN instr(office_normalize(c.case_number), $fullName)=1
               THEN 2 ELSE 3 END
        FROM eligible_cases c JOIN clients u ON u.id=c.client_id
        WHERE ($caseNumber) OR ($opponent) OR $caseNote OR $scopedName
      )
      SELECT * FROM hits ORDER BY rank, name, client_id, case_id LIMIT 200
      ''', variables: args).get();

    return rows
        .map(
          (row) => SearchHit(
            row.read<String>('client_id'),
            row.read<String>('name'),
            row.read<int>('is_archived') != 0,
            caseId: row.readNullable<String>('case_id'),
            caseNumber: row.readNullable<String>('case_number'),
            match: row.read<String>('match_type'),
          ),
        )
        .toList();
  });
}
