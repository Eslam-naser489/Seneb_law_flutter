import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../shared/presentation/async_save_dialog.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/office_models.dart';

class AssignmentScreen extends StatefulWidget {
  const AssignmentScreen({
    super.key,
    required this.recordId,
    required this.forCase,
  });
  final String recordId;
  final bool forCase;
  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen> {
  ScopedAppRepository get _repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  Future<(List<AssignmentView>, List<OfficeLawyerEntity>)> _load() async => (
    await _repo.assignments(widget.recordId, forCase: widget.forCase),
    _repo.isOwner ? await _repo.getLawyers() : <OfficeLawyerEntity>[],
  );
  late var _data = _load();
  void _refresh() => setState(() => _data = _load());

  Future<void> _assign(List<OfficeLawyerEntity> members, bool hasLead) async {
    String? person;
    var role = widget.forCase ? 'ASSISTANT' : 'RESPONSIBLE';
    var replace = false;
    final reason = TextEditingController();
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: 'إسناد جديد',
          errorMessage: workspaceError,
          content: StatefulBuilder(
            builder: (context, update) => SizedBox(
              width: 410,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: person,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'عضو الفريق'),
                    items: [
                      for (final member in members)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(
                            member.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => update(() => person = id),
                  ),
                  if (widget.forCase)
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(
                        labelText: 'دور القضية',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ASSISTANT',
                          child: Text('محامٍ مساعد'),
                        ),
                        DropdownMenuItem(
                          value: 'LEAD',
                          child: Text('محامٍ رئيسي'),
                        ),
                      ],
                      onChanged: (value) => update(() => role = value!),
                    ),
                  if (hasLead && role == 'LEAD')
                    CheckboxListTile(
                      value: replace,
                      onChanged: (value) =>
                          update(() => replace = value ?? false),
                      title: const Text('استبدال المحامي الرئيسي الحالي'),
                    ),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'سبب الإسناد'),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تاريخ السريان'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy', 'en').format(DateTime.now()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          validate: () => person == null
              ? 'اختر عضو الفريق.'
              : reason.text.trim().isEmpty
              ? 'اكتب سبب الإسناد.'
              : null,
          onSave: () async {
            await _repo.assign(
              widget.recordId,
              person!,
              forCase: widget.forCase,
              role: role,
              reason: reason.text,
              replaceLead: replace,
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      reason.dispose();
    }
  }

  Future<void> _end(AssignmentView assignment) async {
    final reason = TextEditingController();
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: 'إنهاء إسناد ${assignment.name}',
          errorMessage: workspaceError,
          content: Column(
            children: [
              const Text(
                'قد تتغير صلاحية هذا المستخدم في عرض بيانات الموكل أو القضية.',
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'سبب الإنهاء'),
              ),
            ],
          ),
          validate: () =>
              reason.text.trim().isEmpty ? 'اكتب سبب الإنهاء.' : null,
          onSave: () async {
            await _repo.endAssignment(
              widget.recordId,
              assignment.id,
              forCase: widget.forCase,
              reason: reason.text,
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.forCase ? 'إسناد القضية' : 'إسناد الموكل'),
    ),
    body: WorkspaceLoad(
      future: _data,
      retry: _refresh,
      buildData: (d) {
        final (rows, members) = d;
        final active = rows.where((a) => a.endedAt == null).toList();
        final ended = rows.where((a) => a.endedAt != null).toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_repo.isOwner)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: members.isEmpty
                      ? null
                      : () => _assign(
                          members,
                          active.any((a) => a.role == 'LEAD'),
                        ),
                  icon: const Icon(Icons.person_add),
                  label: const Text('إسناد جديد'),
                ),
              ),
            const ListTile(title: Text('الإسنادات الحالية')),
            if (active.isEmpty)
              const ListTile(title: Text('لا توجد إسنادات حالية.')),
            for (final row in active) _tile(row),
            const Divider(),
            const ListTile(title: Text('سجل الإسنادات المنتهية')),
            if (ended.isEmpty)
              const ListTile(title: Text('لا توجد إسنادات منتهية.')),
            for (final row in ended) _tile(row),
          ],
        );
      },
    ),
  );

  Widget _tile(AssignmentView row) => Card(
    child: ListTile(
      title: Text(row.name),
      subtitle: Text(
        [
          switch (row.role) {
            'LEAD' => 'محامٍ رئيسي',
            'ASSISTANT' => 'محامٍ مساعد',
            _ => 'مسؤول عن الموكل',
          },
          if (row.startedAt != null)
            'بدأ ${DateFormat('dd/MM/yyyy', 'en').format(row.startedAt!.toLocal())}'
          else
            'تاريخ البدء غير معروف',
          if (row.endedAt != null)
            'انتهى ${DateFormat('dd/MM/yyyy', 'en').format(row.endedAt!.toLocal())}',
          if (row.reason != null) row.reason!,
        ].join(' · '),
      ),
      trailing: row.endedAt == null && _repo.isOwner
          ? IconButton(
              tooltip: 'إنهاء الإسناد',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () => _end(row),
            )
          : null,
    ),
  );
}
