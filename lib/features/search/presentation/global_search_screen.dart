import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../domain/search_models.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});
  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _text = TextEditingController();
  ScopedAppRepository get _repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  Timer? _debounce;
  int _version = 0;
  late final Future<List<OfficeLawyerEntity>> _lawyers = _repo.getLawyers();
  List<SearchHit> _hits = [];
  String? _lawyer, _status;
  ArchiveFilter _archive = ArchiveFilter.active;
  bool _loading = false, _failed = false;

  void _search({bool now = false}) {
    _debounce?.cancel();
    final version = ++_version;
    final query = _text.text.trim();
    final filter = SearchFilter(
      lawyerId: _lawyer,
      status: _status,
      archive: _archive,
    );
    setState(() {
      _hits = [];
      _failed = false;
      _loading = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    Future<void> run() async {
      try {
        final result = await _repo.search(query, filter);
        if (mounted && version == _version) {
          setState(() {
            _hits = result;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted && version == _version) {
          setState(() {
            _failed = true;
            _loading = false;
          });
        }
      }
    }

    if (now) {
      unawaited(run());
    } else {
      _debounce = Timer(const Duration(milliseconds: 300), run);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _version++;
    _text.dispose();
    super.dispose();
  }

  Future<void> _open(SearchHit hit) async {
    final location = hit.caseId == null
        ? '/client/${Uri.encodeComponent(hit.clientId)}'
        : '/case/${Uri.encodeComponent(hit.caseId!)}';
    await context.push(location);
    if (mounted) _search(now: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('البحث الموحد')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: TextField(
            controller: _text,
            maxLength: 120,
            autofocus: true,
            decoration: InputDecoration(
              labelText:
                  'الاسم، الهاتف، الرقم القومي، القضية، الخصم أو الملاحظات',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _text.clear();
                  _search(now: true);
                },
              ),
            ),
            onChanged: (_) => _search(),
            onSubmitted: (_) => _search(now: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FutureBuilder(
                future: _lawyers,
                builder: (context, snapshot) => SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('lawyer-$_lawyer'),
                    initialValue: _lawyer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المحامي'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل المحامين'),
                      ),
                      for (final p in snapshot.data ?? <OfficeLawyerEntity>[])
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      _lawyer = value;
                      _search(now: true);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('status-$_status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'حالة القضية'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('كل الحالات')),
                    DropdownMenuItem(value: 'ACTIVE', child: Text('جارية')),
                    DropdownMenuItem(value: 'ON_HOLD', child: Text('موقوفة')),
                    DropdownMenuItem(value: 'CLOSED', child: Text('منتهية')),
                    DropdownMenuItem(value: 'ARCHIVED', child: Text('مؤرشفة')),
                    DropdownMenuItem(
                      value: 'LEGACY',
                      child: Text('حالة قديمة'),
                    ),
                  ],
                  onChanged: (value) {
                    _status = value;
                    _search(now: true);
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<ArchiveFilter>(
                  key: ValueKey(_archive),
                  initialValue: _archive,
                    isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الموكلون'),
                  items: const [
                    DropdownMenuItem(
                      value: ArchiveFilter.active,
                      child: Text('النشطون'),
                    ),
                    DropdownMenuItem(
                      value: ArchiveFilter.archived,
                      child: Text('المؤرشفون'),
                    ),
                    DropdownMenuItem(
                      value: ArchiveFilter.all,
                      child: Text('الكل'),
                    ),
                  ],
                  onChanged: (value) {
                    _archive = value!;
                    _search(now: true);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _results()),
      ],
    ),
  );

  Widget _results() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: () => _search(now: true),
          child: const Text('تعذر البحث. إعادة المحاولة'),
        ),
      );
    }
    if (_text.text.trim().isEmpty) {
      return const Center(child: Text('اكتب اسمًا أو رقمًا للبحث.'));
    }
    if (_hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد نتائج مطابقة.'),
            if (_lawyer != null ||
                _status != null ||
                _archive != ArchiveFilter.active)
              TextButton(
                onPressed: () {
                  _lawyer = null;
                  _status = null;
                  _archive = ArchiveFilter.active;
                  _search(now: true);
                },
                child: const Text('مسح الفلاتر'),
              ),
          ],
        ),
      );
    }
    final groups = <String, List<SearchHit>>{};
    for (final hit in _hits) {
      groups.putIfAbsent(hit.clientId, () => []).add(hit);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_hits.length == 200)
          const ListTile(title: Text('تُعرض أول ٢٠٠ نتيجة. ضيّق نطاق البحث.')),
        for (final group in groups.values)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(group.first.name),
                  subtitle: Text(
                    [
                      if (group.first.archived) 'مؤرشف',
                      for (final hit in group.where((h) => h.caseId == null))
                        _match(hit.match),
                    ].join(' · '),
                  ),
                  onTap: () => _open(
                    SearchHit(
                      group.first.clientId,
                      group.first.name,
                      group.first.archived,
                    ),
                  ),
                ),
                for (final hit in group.where((h) => h.caseId != null))
                  ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 48,
                      end: 16,
                    ),
                    title: Text('قضية ${hit.caseNumber}'),
                    subtitle: Text(_match(hit.match)),
                    onTap: () => _open(hit),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _match(String? code) => switch (code) {
    'PHONE' => 'تطابق في الهاتف',
    'ID' => 'تطابق في الرقم القومي',
    'CASE' => 'تطابق في رقم القضية',
    'OPPONENT' => 'تطابق في الخصم',
    'NOTE' => 'تطابق في الملاحظات',
    _ => 'تطابق في الاسم',
  };
}
