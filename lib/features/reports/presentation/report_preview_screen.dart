import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_repository.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/report_models.dart';
import '../data/report_pdf.dart';
import '../data/report_sharing.dart';

Uint8List decodeReportLogo(String value) => base64Decode(value);
Future<void> validateReportLogo(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 1200,
    targetHeight: 1200,
  );
  final frame = await codec.getNextFrame();
  frame.image.dispose();
  codec.dispose();
}

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({
    super.key,
    required this.repo,
    this.prepared,
    this.pdf,
    this.stored,
    this.gateway,
  });
  final ScopedAppRepository repo;
  final PreparedReport? prepared;
  final Uint8List? pdf;
  final ReportBundle? stored;
  final ShareGateway? gateway;
  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final operationKey = const Uuid().v4();
  late ReportBundle? bundle = widget.stored;
  late final Uint8List pdf = widget.pdf ?? widget.stored!.pdf;
  late List<Uint8List> images = widget.stored?.images ?? [];
  String format = 'TEXT', recipient = '';
  bool reviewed = false, busy = false;
  String get text => bundle?.report.textContent ?? widget.prepared!.text;
  late Future<void> ready = load();
  Future<void> load() async {
    if (bundle != null) {
      bundle = await widget.repo.readReport(bundle!.report.id);
      recipient = await widget.repo.reportRecipient(bundle!.report.id);
    } else {
      final req = widget.prepared!.request;
      final profile = await widget.repo.clientProfile(req.clientId);
      recipient = profile.fullAccess
          ? (profile.client.whatsappNumber ?? profile.client.phone ?? '')
          : '';
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        message(
          workspaceError(e) ??
              'تعذرت العملية. احتُفظ بالتقرير؛ يمكنك إعادة المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> ensureStored() async {
    bundle ??= await widget.repo.finalizeReport(
      widget.prepared!,
      pdf,
      operationKey: operationKey,
    );
    if (images.isNotEmpty && bundle!.images.isEmpty) {
      bundle = await widget.repo.addReportImages(
        bundle!.report.id,
        reportHash(pdf),
        images,
      );
    }
  }

  Future<void> chooseFormat(String value) async {
    if (busy) return;
    setState(() {
      format = value;
      reviewed = false;
    });
    if (value != 'TEXT' && images.isEmpty) {
      await run(() async {
        final result = await ReportPdf.images(pdf);
        if (mounted) setState(() => images = result);
      });
    }
  }

  Future<void> share(String channel, {String? selectedFormat}) async {
    if (!reviewed) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مراجعة المستلم والمحتوى'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'قد يحتوي المستند على بيانات سرية. تأكد من المستلم قبل الإرسال.',
              ),
              Text(
                recipient.isEmpty
                    ? 'سيُختار المستلم في التطبيق الخارجي.'
                    : 'رقم التواصل المعروض: $recipient',
              ),
              if (channel.startsWith('WHATSAPP'))
                const Text(
                  'سيُفتح النص كمسودة وقد يظهر في سجل المتصفح. لا يُرسل تلقائيًا ولا يرفق ملفات؛ أرفق الملف المحفوظ يدويًا.',
                ),
              if (channel == 'NATIVE')
                const Text(
                  'اختر التطبيق والمستلم بنفسك. إن اخترت واتساب فتأكد من موافقة الموكل. قد لا يقبل Facebook أو Messenger النص؛ استخدم صورة أو انسخ النص يدويًا.',
                ),
              if (channel == 'COPY')
                const Text(
                  'سيصبح النص متاحًا لحافظة النظام؛ امسحه بعد استخدامه.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة باختياري'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    await run(() async {
      await ensureStored();
      final result = await ReportSharing(widget.repo, gateway: widget.gateway)
          .share(
            bundle!,
            recipient: recipient,
            channel: channel,
            format: selectedFormat ?? format,
            reviewed: true,
          );
      if (mounted) {
        message(
          result.errorCode?.startsWith('PARTIAL_EXPORT') == true
              ? 'حُفظت بعض الصفحات فقط. أعد الحفظ لإكمالها.'
              : shareStatusLabels[result.status]!,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('معاينة التقرير'),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('تعديل / رجوع'),
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: ready,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return const Center(
            child: Text(
              'تعذر فتح المعاينة أو انتهت الصلاحية. ارجع وأعد المحاولة.',
            ),
          );
        }
        final loaded = format == 'TEXT' || images.isNotEmpty;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'TEXT': 'نص',
                    'PDF': 'PDF',
                    'PNG': 'صور',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: format == entry.key,
                      onSelected: busy ? null : (_) => chooseFormat(entry.key),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (format) {
                'PDF' || 'PNG' =>
                  images.isEmpty
                      ? Center(
                          child: Text(
                            busy
                                ? 'جارٍ تجهيز الصفحات…'
                                : 'تعذر تجهيز الصفحات؛ أعد اختيار الصيغة للمحاولة.',
                          ),
                        )
                      : ListView.builder(
                          itemCount: images.length,
                          itemBuilder: (_, i) => Column(
                            children: [
                              Text('صفحة ${i + 1} من ${images.length}'),
                              Image.memory(images[i], gaplessPlayback: true),
                            ],
                          ),
                        ),
                _ => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(text, textDirection: TextDirection.rtl),
                ),
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        dense: true,
                        title: const Text('راجعت المحتوى واسم الموكل والمستلم'),
                        value: reviewed,
                        onChanged: busy || !loaded
                            ? null
                            : (v) => setState(() => reviewed = v ?? false),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton(
                            onPressed: busy || !reviewed
                                ? null
                                : () => run(() async {
                                    await ensureStored();
                                    if (mounted) {
                                      message('حُفظت نسخة ثابتة من التقرير.');
                                    }
                                  }),
                            child: const Text('حفظ التقرير'),
                          ),
                          FilledButton.icon(
                            onPressed: busy || !reviewed
                                ? null
                                : () => share('NATIVE'),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('مشاركة'),
                          ),
                          if (format == 'TEXT')
                            OutlinedButton(
                              onPressed: busy || !reviewed
                                  ? null
                                  : () => share('WHATSAPP'),
                              child: const Text('واتساب مباشر'),
                            ),
                          if (format != 'TEXT')
                            OutlinedButton(
                              onPressed: busy || !reviewed
                                  ? null
                                  : () => share('SAVE'),
                              child: const Text('حفظ الملف'),
                            ),
                          if (format == 'TEXT')
                            OutlinedButton(
                              onPressed: busy || !reviewed
                                  ? null
                                  : () => share('COPY'),
                              child: const Text('نسخ النص'),
                            ),
                          if (format == 'TEXT')
                            OutlinedButton(
                              onPressed: busy || !reviewed
                                  ? null
                                  : () => share('WHATSAPP_WEB'),
                              child: const Text('فتح واتساب ويب'),
                            ),
                          if (format == 'PDF')
                            OutlinedButton(
                              onPressed: busy || !reviewed
                                  ? null
                                  : () => share('PRINT'),
                              child: const Text('طباعة'),
                            ),
                        ],
                      ),
                      const Text(
                        'بديل المشاركة: احفظ الملف، ثم اختر «نص» لنسخه وفتح واتساب ويب. أرفق الملف يدويًا؛ الفتح لا يعني الإرسال.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (busy) const Text('جارٍ تنفيذ العملية…'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
