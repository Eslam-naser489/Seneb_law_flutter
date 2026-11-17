import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../reports/data/report_sharing.dart';
import '../domain/docx_engine.dart';
import '../domain/word_draft.dart';

class WordLibraryScreen extends StatefulWidget {
  const WordLibraryScreen({super.key, this.clientId, this.caseId});
  final String? clientId, caseId;
  @override
  State<WordLibraryScreen> createState() => _WordLibraryState();
}

class _WordLibraryState extends State<WordLibraryScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<List<WordTemplate>> data = repo.wordTemplates();
  bool busy = false;
  String filter = '';
  void refresh() => setState(() => data = repo.wordTemplates());
  Future<void> import() async {
    setState(() => busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (files.isEmpty) return;
      final length = await files.single.length();
      if (length == null || length > DocxEngine.maxBytes ||
          !files.single.name.toLowerCase().endsWith('.docx')) {
        throw const TemplateFailure('اختر DOCX لا يتجاوز 10 ميجابايت.');
      }
      final bytes = await files.single.readAsBytes();
      final fields = DocxEngine.inspect(bytes).toList()..sort();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ImportDialog(bytes: bytes, fields: fields, repo: repo),
      );
      if (mounted) refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('قوالب Word'),
      actions: [
        if (repo.isOwner)
          IconButton(
            tooltip: 'رفع قالب Word',
            onPressed: busy ? null : import,
            icon: const Icon(Icons.upload_file),
          ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'حقول القالب مثل {{client_name}}. كل استيراد معدل بالاسم نفسه يحفظ إصدارًا جديدًا. إدارة القوالب لمالك المكتب.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'بحث بالاسم أو التصنيف',
            ),
            onChanged: (v) => setState(() => filter = v.trim()),
          ),
        ),
        if (widget.clientId != null)
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WordHistoryScreen(
                  clientId: widget.clientId!,
                  caseId: widget.caseId,
                ),
              ),
            ),
            icon: const Icon(Icons.folder_open),
            label: const Text('المستندات المولدة'),
          ),
        Expanded(
          child: FutureBuilder<List<WordTemplate>>(
            future: data,
            builder: (context, s) {
              if (s.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: refresh,
                    child: Text('${s.error}\nإعادة المحاولة'),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = s.data!
                  .where(
                    (t) =>
                        t.name.contains(filter) || t.category.contains(filter),
                  )
                  .toList();
              if (rows.isEmpty) {
                return const Center(
                  child: Text(
                    'لا توجد قوالب مطابقة. يمكن للمالك رفع قالب Word.',
                  ),
                );
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final t = rows[i];
                  return ListTile(
                    title: Text('${t.name} — إصدار ${t.version}'),
                    subtitle: Text(
                      '${t.category} · تم الفحص\n${(jsonDecode(t.fieldsJson) as List).join('، ')}',
                    ),
                    isThreeLine: true,
                    trailing: widget.clientId == null
                        ? null
                        : const Icon(Icons.chevron_left),
                    onTap: () => widget.clientId == null
                        ? showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(t.name),
                              content: const Text(
                                'افتح ملف الموكل أو القضية واختر قوالب Word لإنشاء مستند.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('حسنًا'),
                                ),
                              ],
                            ),
                          )
                        : Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => WordGenerateScreen(
                                templateId: t.id,
                                clientId: widget.clientId!,
                                caseId: widget.caseId,
                              ),
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.bytes,
    required this.fields,
    required this.repo,
  });
  final Uint8List bytes;
  final List<String> fields;
  final ScopedAppRepository repo;
  @override
  State<_ImportDialog> createState() => _ImportState();
}

class _ImportState extends State<_ImportDialog> {
  final name = TextEditingController(), category = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    category.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.repo.importWordTemplate(
        name.text,
        category.text,
        widget.bytes,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('فحص وتفعيل القالب'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'اسم القالب'),
            ),
            TextField(
              controller: category,
              decoration: const InputDecoration(labelText: 'التصنيف'),
            ),
            Text('الحقول المطلوبة: ${widget.fields.join('، ')}'),
            const Text(
              'تأكد أن القالب لا يحتوي بيانات موكلين حقيقية؛ يظهر للمحامين المخولين في المكتب.',
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('حفظ القالب'),
      ),
    ],
  );
}

class WordGenerateScreen extends StatefulWidget {
  const WordGenerateScreen({
    super.key,
    required this.templateId,
    required this.clientId,
    this.caseId,
  });
  final String templateId, clientId;
  final String? caseId;
  @override
  State<WordGenerateScreen> createState() => _GenerateState();
}

class _GenerateState extends State<WordGenerateScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  final fields = <String, TextEditingController>{};
  late Future<WordContext> data = load();
  String operation = const Uuid().v4();
  bool busy = false, sensitive = false, reviewed = false;
  String? error;
  Future<WordContext> load() async {
    final result = await repo.wordContext(
      widget.templateId,
      widget.clientId,
      caseId: widget.caseId,
    );
    for (final e in result.values.entries) {
      fields[e.key] = TextEditingController(text: e.value);
    }
    return result;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> generate() async {
    setState(() => busy = true);
    try {
      final draft = await repo.prepareWord(
        widget.templateId,
        widget.clientId,
        caseId: widget.caseId,
        values: {for (final e in fields.entries) e.key: e.value.text},
        sensitiveReviewed: sensitive,
      );
      final doc = await repo.finalizeWord(
        draft,
        operationKey: operation,
        reviewed: reviewed,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => WordDocumentScreen(id: doc.id)),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مراجعة بيانات المستند')),
    body: FutureBuilder<WordContext>(
      future: data,
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${s.data!.template.name} — إصدار ${s.data!.template.version}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'هذه مراجعة بيانات وليست معاينة لتنسيق Word. التعديلات تخص هذا المستند فقط ولا تغيّر ملف الموكل أو القضية.',
                ),
                for (final e in fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: e.value,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText:
                            wordFieldLabels[e.key] ?? 'حقل إضافي: ${e.key}',
                        helperText: e.value.text == s.data!.values[e.key]
                            ? 'من المصدر أو قيمة فارغة'
                            : 'تعديل لهذا المستند فقط',
                      ),
                      onChanged: (_) => setState(() {
                        reviewed = false;
                        sensitive = false;
                        operation = const Uuid().v4();
                      }),
                    ),
                  ),
                if (fields.containsKey('client_national_id'))
                  CheckboxListTile(
                    value: sensitive,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => sensitive = v ?? false),
                    title: const Text('راجعت الرقم القومي وأوافق على إدراجه'),
                  ),
                CheckboxListTile(
                  value: reviewed,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => reviewed = v ?? false),
                  title: const Text('راجعت جميع البيانات والحقول المطلوبة'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  onPressed: busy || !reviewed ? null : generate,
                  child: Text(busy ? 'جارٍ الحفظ…' : 'إنشاء المستند وحفظه'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class WordHistoryScreen extends StatefulWidget {
  const WordHistoryScreen({super.key, required this.clientId, this.caseId});
  final String clientId;
  final String? caseId;
  @override
  State<WordHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<WordHistoryScreen> {
  late Future<List<WordDocument>> data =
      (context.read<AppRepository>() as ScopedAppRepository).wordDocuments(
        widget.clientId,
        caseId: widget.caseId,
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المستندات المولدة')),
    body: FutureBuilder<List<WordDocument>>(
      future: data,
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) {
          return const Center(
            child: Text(
              'لم تُنشأ مستندات بعد. اختر قالب Word من ملف الموكل أو القضية.',
            ),
          );
        }
        return ListView(
          children: [
            for (final d in s.data!)
              ListTile(
                title: Text(d.title),
                subtitle: Text(d.createdAt.toLocal().toString()),
                leading: const Icon(Icons.description),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => WordDocumentScreen(id: d.id),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class WordDocumentScreen extends StatefulWidget {
  const WordDocumentScreen({super.key, required this.id});
  final String id;
  @override
  State<WordDocumentScreen> createState() => _DocumentState();
}

class _DocumentState extends State<WordDocumentScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<WordDocument> data = repo.readWordDocument(widget.id);
  late Future<List<WordShareAttempt>> attempts = repo.wordShareHistory(
    widget.id,
  );
  bool reviewed = false, busy = false;
  String? message;
  Future<void> handoff(WordDocument doc, String channel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('مراجعة الخصوصية'),
        content: Text(
          channel == 'NATIVE'
              ? 'تأكد من المستلم وموافقته قبل مشاركة البيانات الحساسة. فتح تطبيق المشاركة ليس إثبات إرسال.'
              : 'ستخرج نسخة إلى البرنامج المختار أو مكان الحفظ. التعديلات الخارجية لا تغيّر النسخة المحفوظة في المكتب.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    String? id;
    try {
      id = await repo.beginWordHandoff(
        doc.id,
        channel,
        checksum: doc.checksum,
        reviewed: reviewed,
      );
      final fresh = await repo.readWordDocument(doc.id);
      final attempt = id;
      final result = await NativeShareGateway().handoffWord(
        fresh.bytes,
        channel,
        () => repo.authorizeWordHandoff(attempt),
      );
      await repo.finishWordHandoff(id, result.status);
      if (mounted) setState(() => message = _status(result.status));
    } catch (e) {
      if (id != null) {
        try {
          await repo.finishWordHandoff(id, 'FAILED');
        } catch (_) {}
      }
      if (mounted) setState(() => message = 'تعذر الإجراء: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          attempts = repo.wordShareHistory(widget.id);
        });
      }
    }
  }

  static String _status(String s) =>
      const {
        'STARTED': 'بدأت — النتيجة غير مؤكدة',
        'OPENED': 'فُتح البرنامج — ليس إثبات إرسال',
        'SAVED': 'حُفظت نسخة',
        'CANCELLED': 'أُلغيت',
        'FAILED': 'تعذر الإجراء',
        'UNAVAILABLE': 'النتيجة غير متاحة',
      }[s] ??
      s;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مراجعة المستند ومشاركته')),
    body: FutureBuilder<WordDocument>(
      future: data,
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(d.title, style: Theme.of(context).textTheme.headlineSmall),
            const Text(
              'افتح النسخة الأصلية للمراجعة في Word أو برنامج متوافق. هذه الشاشة تعرض البيانات ولا تعرض تنسيق الصفحات. احفظ الملف للإرفاق اليدوي عند غياب تطبيق مشاركة. تحويل PDF اختياري خارج التطبيق.',
            ),
            for (final e in (jsonDecode(d.inputJson) as Map).entries)
              ListTile(
                title: Text(wordFieldLabels[e.key] ?? e.key.toString()),
                subtitle: Text(e.value.toString()),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => handoff(d, 'OPEN'),
                  child: const Text('فتح المستند للمراجعة'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => handoff(d, 'SAVE'),
                  child: const Text('حفظ DOCX'),
                ),
              ],
            ),
            CheckboxListTile(
              value: reviewed,
              onChanged: busy
                  ? null
                  : (v) => setState(() => reviewed = v ?? false),
              title: const Text(
                'راجعت النسخة الأصلية ومحتواها وتنسيقها قبل المشاركة',
              ),
            ),
            FilledButton(
              onPressed: busy || !reviewed ? null : () => handoff(d, 'NATIVE'),
              child: const Text('مشاركة المستند'),
            ),
            if (message != null) Text(message!),
            const Divider(),
            const Text('سجل الفتح والحفظ والمشاركة'),
            FutureBuilder<List<WordShareAttempt>>(
              future: attempts,
              builder: (context, a) => Column(
                children: [
                  if (a.hasError) Text('${a.error}'),
                  for (final row in a.data ?? <WordShareAttempt>[])
                    ListTile(
                      title: Text(_status(row.status)),
                      subtitle: Text(
                        '${const {'OPEN': 'فتح للمراجعة', 'SAVE': 'حفظ نسخة', 'NATIVE': 'مشاركة'}[row.channel]} · ${row.createdAt.toLocal()}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
