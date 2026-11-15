import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/report_models.dart';
import '../data/report_pdf.dart';
import 'report_preview_screen.dart';

class ReportComposerScreen extends StatefulWidget {
  const ReportComposerScreen({super.key, required this.caseId});
  final String caseId;
  @override
  State<ReportComposerScreen> createState() => _ReportComposerScreenState();
}

class _ReportComposerScreenState extends State<ReportComposerScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  final fields = {
    for (final key in reportSectionLabels.keys.where((k) => k != 'finance'))
      key: TextEditingController(),
  };
  final selected = <String>{};
  List<ReportTemplate> templates = [];
  bool busy = false;
  late Future<ReportContext> data = load();
  Future<ReportContext> load() async {
    final value = await repo.reportContext(widget.caseId);
    templates = await repo.reportTemplates();
    for (final e in value.defaults.entries) {
      fields[e.key]!.text = e.value;
      selected.add(e.key);
    }
    return value;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> template(ReportTemplate template) async {
    final field = TextEditingController();
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: template.fieldLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (field.text.trim().isNotEmpty) {
                Navigator.pop(ctx, field.text.trim());
              }
            },
            child: const Text('إضافة للنص'),
          ),
        ],
      ),
    );
    field.dispose();
    if (ok == null || !mounted) return;
    setState(() {
      fields['development']!.text = template.body.replaceAll('{{value}}', ok);
      selected.add('development');
    });
  }

  Future<void> preview(ReportContext source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final prepared = await repo.prepareReport(
        ReportRequest(
          clientId: source.clientId,
          caseId: source.caseId,
          includeFinance: selected.contains('finance'),
          sections: {
            for (final key in selected.where((k) => k != 'finance'))
              key: fields[key]!.text,
          },
        ),
      );
      final pdf = await ReportPdf.build(prepared);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReportPreviewScreen(repo: repo, prepared: prepared, pdf: pdf),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              workspaceError(e) ??
                  'تعذر إنشاء المعاينة. احتُفظ بالمحتوى للمحاولة مجددًا.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('إعداد تقرير للموكل'),
      actions: [
        if (repo.isOwner)
          IconButton(
            tooltip: 'اسم المكتب وشعاره',
            icon: const Icon(Icons.business_outlined),
            onPressed: busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportBrandingScreen(repo: repo),
                    ),
                  ),
          ),
      ],
    ),
    body: WorkspaceLoad(
      future: data,
      retry: () => setState(() => data = load()),
      buildData: (source) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            source.clientName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'حدد المحتوى الموجه للموكل. التعديل هنا لا يغير بيانات القضية.',
          ),
          if (source.recipient.isNotEmpty)
            Text(
              'رقم التواصل: ${source.recipient}',
              textDirection: TextDirection.ltr,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in templates)
                ActionChip(
                  label: Text(t.name),
                  onPressed: busy ? null : () => template(t),
                ),
            ],
          ),
          if (source.eligibleNotes.isNotEmpty)
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'إضافة ملاحظة مؤهلة للتقرير باختيارك',
              ),
              items: [
                for (final n in source.eligibleNotes)
                  DropdownMenuItem(
                    value: n.id,
                    child: Text(
                      n.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (id) {
                      if (id != null) {
                        setState(() {
                          fields['development']!.text = source.eligibleNotes
                              .firstWhere((n) => n.id == id)
                              .content;
                          selected.add('development');
                        });
                      }
                    },
            ),
          for (final entry in reportSectionLabels.entries) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              value: selected.contains(entry.key),
              subtitle: entry.key == 'finance'
                  ? Text(
                      source.financeAllowed
                          ? 'غير محدد افتراضيًا؛ حساب هذه القضية فقط.'
                          : 'الحساب المالي خارج نطاق صلاحياتك.',
                    )
                  : null,
              onChanged:
                  busy || (entry.key == 'finance' && !source.financeAllowed)
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(entry.key);
                      } else {
                        selected.remove(entry.key);
                      }
                    }),
            ),
            if (selected.contains(entry.key) && entry.key != 'finance')
              TextField(
                controller: fields[entry.key],
                enabled: !busy,
                minLines: 2,
                maxLines: 8,
                maxLength: 10000,
                decoration: InputDecoration(
                  labelText: entry.value,
                  border: const OutlineInputBorder(),
                ),
              ),
          ],
          const Text(
            'الرقم القومي والملاحظات الداخلية لا تُضاف تلقائيًا. راجع أي نص تكتبه أو تلصقه.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : () => preview(source),
            icon: const Icon(Icons.preview_outlined),
            label: Text(busy ? 'جارٍ تجهيز المعاينة…' : 'معاينة التقرير'),
          ),
        ],
      ),
    ),
  );
}

class ReportBrandingScreen extends StatefulWidget {
  const ReportBrandingScreen({super.key, required this.repo});
  final ScopedAppRepository repo;
  @override
  State<ReportBrandingScreen> createState() => _ReportBrandingScreenState();
}

class _ReportBrandingScreenState extends State<ReportBrandingScreen> {
  final name = TextEditingController();
  Uint8List? logo;
  bool busy = false;
  late Future<void> ready = load();
  Future<void> load() async {
    final brand = await widget.repo.reportBranding();
    name.text = brand['name'] as String;
    logo = brand['logo'] == null
        ? null
        : decodeReportLogo(brand['logo'] as String);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(workspaceError(e) ?? 'تعذر تحديث هوية المكتب.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('هوية المكتب في التقارير')),
    body: FutureBuilder<void>(
      future: ready,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return const Center(child: Text('تعذر تحميل هوية المكتب.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: name,
              maxLength: 150,
              decoration: const InputDecoration(labelText: 'اسم المكتب'),
            ),
            if (logo != null)
              Image.memory(
                logo!,
                height: 90,
                errorBuilder: (_, _, _) => const Text('الصورة غير سليمة'),
              ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final chosen = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['png', 'jpg', 'jpeg'],
                      );
                      if (chosen.isEmpty) return;
                      final bytes = await chosen.single.readAsBytes();
                      if (bytes.length > 1000000) {
                        throw const FormatException(
                          'اختر صورة لا تزيد على ١ ميجابايت.',
                        );
                      }
                      await validateReportLogo(bytes);
                      setState(() => logo = bytes);
                    }),
              child: const Text('اختيار الشعار'),
            ),
            TextButton(
              onPressed: busy ? null : () => setState(() => logo = null),
              child: const Text('إزالة الشعار'),
            ),
            const Text('التقارير المحفوظة سابقًا تحتفظ بالهوية القديمة.'),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await widget.repo.saveReportBranding(name.text, logo);
                      if (context.mounted) Navigator.pop(context);
                    }),
              child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ'),
            ),
          ],
        );
      },
    ),
  );
}
