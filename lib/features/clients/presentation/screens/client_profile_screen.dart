import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_repository.dart';
import '../../../../core/database/database.dart';
import '../../../search/data/arabic_search.dart';
import '../../../shared/presentation/async_save_dialog.dart';
import '../../../shared/presentation/workspace_load.dart';
import '../../domain/client_profile.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key, required this.id});
  final String id;
  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  ScopedAppRepository get _repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<ClientProfile> _data = _repo.clientProfile(widget.id);
  void _refresh() => setState(() => _data = _repo.clientProfile(widget.id));
  String _date(DateTime value) =>
      DateFormat('dd/MM/yyyy', 'en').format(value.toLocal());

  static const _consents = {
    'UNKNOWN': 'لم تُسجل الموافقة',
    'GRANTED': 'وافق الموكل',
    'WITHDRAWN': 'سحب الموكل الموافقة',
  };

  Map<String, (String, String?)> _fields(ClientEntity c) => {
    'phone': ('الهاتف الأساسي', c.phone),
    'phoneSecondary': ('الهاتف الثاني', c.phoneSecondary),
    'whatsappNumber': ('رقم واتساب', c.whatsappNumber),
    'nationalId': ('الرقم القومي', c.nationalId),
    'address': ('العنوان', c.address),
    'email': ('البريد الإلكتروني', c.email),
    'occupation': ('المهنة', c.occupation),
    'referralSource': ('مصدر الإحالة', c.referralSource),
    'notes': ('ملاحظات داخلية', c.notes),
  };

  Future<void> _edit(ClientEntity client) async {
    final name = TextEditingController(text: client.name);
    final source = TextEditingController(text: client.consentSource);
    final fields = _fields(client);
    final controllers = fields.map(
      (key, field) => MapEntry(key, TextEditingController(text: field.$2)),
    );
    var consent = client.whatsappConsentStatus;
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: 'تعديل بيانات الموكل',
          errorMessage: workspaceError,
          content: StatefulBuilder(
            builder: (context, update) => SizedBox(
              width: 520,
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'اسم الموكل'),
                  ),
                  for (final entry in fields.entries)
                    TextField(
                      controller: controllers[entry.key],
                      decoration: InputDecoration(labelText: entry.value.$1),
                      textDirection:
                          [
                            'phone',
                            'phoneSecondary',
                            'whatsappNumber',
                            'nationalId',
                            'email',
                          ].contains(entry.key)
                          ? TextDirection.ltr
                          : null,
                      maxLines: entry.key == 'notes' ? 3 : 1,
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: consent,
                    decoration: const InputDecoration(
                      labelText: 'الموافقة على التواصل عبر واتساب',
                    ),
                    items: [
                      for (final entry in _consents.entries)
                        if (entry.key != 'UNKNOWN' ||
                            client.whatsappConsentStatus == 'UNKNOWN')
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                    ],
                    onChanged: (value) => update(() {
                      if (consent != value) source.clear();
                      consent = value!;
                    }),
                  ),
                  if (consent != 'UNKNOWN')
                    TextField(
                      controller: source,
                      decoration: const InputDecoration(
                        labelText: 'مصدر الموافقة أو سحبها',
                      ),
                    ),
                ],
              ),
            ),
          ),
          validate: () => name.text.trim().isEmpty
              ? 'أدخل اسم الموكل.'
              : consent != 'UNKNOWN' && source.text.trim().isEmpty
              ? 'أدخل مصدر الموافقة أو سحبها.'
              : null,
          onSave: () async {
            await _repo.saveClientProfile(
              client.id,
              ClientEdit(
                name.text,
                controllers.map(
                  (key, controller) => MapEntry(key, controller.text),
                ),
                consent: consent,
                consentSource: source.text,
              ),
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      for (final controller in [name, source, ...controllers.values]) {
        controller.dispose();
      }
    }
  }

  Future<void> _archive(ClientEntity client) async {
    final saved = await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: client.isArchived ? 'استعادة الموكل' : 'أرشفة الموكل',
        content: Text(
          client.isArchived
              ? 'سيظهر الموكل في القوائم النشطة.'
              : 'سيظهر الموكل في نتائج البحث عند اختيار المؤرشفين. تبقى سجلاته محفوظة.',
        ),
        validate: () => null,
        errorMessage: workspaceError,
        onSave: () async {
          await _repo.setArchived(client.id, !client.isArchived);
          return true;
        },
      ),
    );
    if (mounted && saved == true) _refresh();
  }

  Future<void> _contact(ClientEntity client, {required bool whatsapp}) async {
    final raw = whatsapp ? client.whatsappNumber : client.phone;
    if (raw == null || raw.trim().isEmpty) return;
    final local = normalizeEgyptianPhone(raw);
    final intl = local.length == 11 && local.startsWith('01')
        ? '20${local.substring(1)}'
        : local;
    if (whatsapp &&
        (client.whatsappConsentStatus != 'GRANTED' ||
            !(RegExp(r'^20[0-9]{10}$').hasMatch(intl) ||
                (raw.startsWith('+') &&
                    intl.length >= 8 &&
                    intl.length <= 15)))) {
      _message('راجع صيغة رقم واتساب الدولي والموافقة المسجلة.');
      return;
    }
    final uri = whatsapp
        ? Uri.https('wa.me', '/$intl')
        : Uri(scheme: 'tel', path: raw.trim());
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // يوفر نسخ الرقم مسارًا يدويًا على الأجهزة دون تطبيق اتصال.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تعذر فتح تطبيق التواصل.'),
        action: SnackBarAction(
          label: 'نسخ الرقم',
          onPressed: () => Clipboard.setData(ClipboardData(text: raw)),
        ),
      ),
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(CaseDocumentEntity doc) async {
    try {
      final path = await _repo.resolveDocumentPath(doc.filePath);
      if (!mounted) return;
      final result = await OpenFilex.open(path);
      if (mounted && result.type != ResultType.done) {
        _message('تعذر فتح الملف.');
      }
    } catch (_) {
      if (mounted) _message('الملف غير متاح أو خارج نطاق صلاحياتك.');
    }
  }

  Widget _list(List<Widget> children, String empty) => children.isEmpty
      ? Center(child: Text(empty))
      : ListView(padding: const EdgeInsets.all(12), children: children);

  Future<void> _navigate(String location) async {
    await context.push(location);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) =>
      WorkspaceLoad(future: _data, retry: _refresh, buildData: _buildProfile);

  Widget _buildProfile(ClientProfile data) {
    final client = data.client;
    final id = Uri.encodeComponent(client.id);
    final editable = data.fullAccess && _repo.canEdit && !client.isArchived;
    final timeline = <(DateTime, String, String)>[
      for (final session in data.sessions)
        (
          session.sessionDate,
          'جلسة: ${session.courtLocation}',
          [
            if (session.circleNumber != null) 'الدائرة ${session.circleNumber}',
            session.decision ?? 'القرار غير مسجل',
          ].join(' · '),
        ),
      for (final note in data.notes)
        (note.createdAt, 'ملاحظة داخلية', note.content),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final tabs = <(String, Widget)>[
      (
        'القضايا',
        _list([
          for (final c in data.cases)
            ListTile(
              leading: const Icon(Icons.gavel),
              title: Text(c.caseNumber),
              subtitle: Text(
                '${c.status} · ${c.opponentName ?? 'الخصم غير مسجل'}',
              ),
              onTap: () => _navigate('/case/${Uri.encodeComponent(c.id)}'),
            ),
        ], 'لا توجد قضايا متاحة لهذا الموكل.'),
      ),
      if (_repo.canEdit)
        (
          'التقارير',
          _list([
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('التقارير وسجل المشاركة'),
              onTap: () => _navigate('/client/$id/reports'),
            ),
            for (final c in data.cases)
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: Text('إرسال تقرير — ${c.caseNumber}'),
                onTap: () =>
                    _navigate('/case/${Uri.encodeComponent(c.id)}/report'),
              ),
          ], 'لا توجد قضايا لإعداد تقرير.'),
        ),
      if (data.fullAccess)
        (
          'البيانات',
          _list([
            for (final entry in _fields(client).entries)
              ListTile(
                title: Text(entry.value.$1),
                subtitle: Text(
                  entry.key == 'nationalId' && client.nationalId != null
                      ? '•••• ${client.nationalId!.length > 4 ? client.nationalId!.substring(client.nationalId!.length - 4) : client.nationalId}'
                      : entry.value.$2 ?? 'غير مسجل',
                  textDirection:
                      [
                            'phone',
                            'phoneSecondary',
                            'whatsappNumber',
                            'nationalId',
                            'email',
                          ].contains(entry.key) &&
                          entry.value.$2 != null
                      ? TextDirection.ltr
                      : null,
                ),
              ),
            ListTile(
              title: const Text('الموافقة على التواصل عبر واتساب'),
              subtitle: Text(
                [
                  _consents[client.whatsappConsentStatus] ??
                      _consents['UNKNOWN']!,
                  if (client.consentSource != null) client.consentSource!,
                  if (client.consentRecordedAt != null)
                    _date(client.consentRecordedAt!),
                ].join(' · '),
              ),
            ),
          ], 'لا توجد بيانات إضافية.'),
        ),
      (
        'التطورات',
        _list([
          for (final item in timeline)
            ListTile(
              title: Text(item.$2),
              subtitle: Text('${_date(item.$1)}\n${item.$3}'),
            ),
        ], 'لا توجد جلسات أو ملاحظات مسجلة.'),
      ),
      (
        'المستندات',
        _list([
          for (final d in data.documents)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(d.title),
              subtitle: Text(
                d.storageStatus == 'AVAILABLE'
                    ? _date(d.uploadedAt)
                    : 'الملف غير متاح',
              ),
              onTap: d.storageStatus == 'AVAILABLE' ? () => _open(d) : null,
            ),
        ], 'لا توجد مستندات محفوظة لهذا الموكل.'),
      ),
      if (data.fullAccess)
        (
          'المحامون',
          _list([
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('عرض سجل الإسناد'),
              onTap: () => _navigate('/client/$id/assignments'),
            ),
            for (final a in data.assignments.where((a) => a.endedAt == null))
              ListTile(
                title: Text(a.name),
                subtitle: const Text('مسؤول عن الموكل'),
              ),
          ], 'لا توجد إسنادات مسجلة.'),
        ),
      if (data.history != null)
        (
          'الحركات القديمة',
          _list([
            const ListTile(
              title: Text('سجل تاريخي للعرض فقط'),
              subtitle: Text('الحركات المعروضة لا تمثل رصيد الموكل.'),
            ),
            if (data.history!.isEmpty)
              const ListTile(
                title: Text('لا توجد حركات قديمة مرتبطة بهذا الموكل.'),
              ),
            for (final t in data.history!)
              ListTile(
                title: Text(t.title),
                subtitle: Text(_date(t.transactionDate)),
                trailing: Text('${t.amount} ج.م'),
              ),
          ], 'لا توجد حركات مسجلة.'),
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(client.name),
          actions: [
            if (editable)
              IconButton(
                tooltip: 'تعديل البيانات',
                onPressed: () => _edit(client),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (_repo.isOwner)
              IconButton(
                tooltip: client.isArchived ? 'استعادة الموكل' : 'أرشفة الموكل',
                onPressed: () => _archive(client),
                icon: Icon(
                  client.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: Column(
          children: [
            if (client.isArchived || !data.fullAccess)
              ListTile(
                dense: true,
                title: Text(
                  client.isArchived
                      ? 'هذا الموكل مؤرشف.'
                      : 'العرض يقتصر على القضايا المسندة إليك.',
                ),
              ),
            if (data.fullAccess)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_repo.canEdit && data.cases.isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('إرسال تقرير'),
                        onPressed: () async {
                          final selected = data.cases.length == 1
                              ? data.cases.single.id
                              : await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => SimpleDialog(
                                    title: const Text('اختر القضية'),
                                    children: [
                                      for (final c in data.cases)
                                        SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.pop(ctx, c.id),
                                          child: Text(c.caseNumber),
                                        ),
                                    ],
                                  ),
                                );
                          if (selected != null && mounted) {
                            await _navigate(
                              '/case/${Uri.encodeComponent(selected)}/report',
                            );
                          }
                        },
                      ),
                    if (_repo.canReadFinance)
                      FilledButton.icon(
                        onPressed: () => _navigate('/client/$id/account'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('الحساب وإضافة دفعة'),
                      ),
                    if (client.phone != null)
                      OutlinedButton.icon(
                        onPressed: () => _contact(client, whatsapp: false),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('اتصال'),
                      ),
                    if (client.whatsappNumber != null &&
                        client.whatsappConsentStatus == 'GRANTED')
                      OutlinedButton.icon(
                        onPressed: () => _contact(client, whatsapp: true),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('واتساب'),
                      ),
                    if (editable)
                      FilledButton.icon(
                        onPressed: () => _navigate('/add-case?client=$id'),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة قضية'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.$2]),
            ),
          ],
        ),
      ),
    );
  }
}
