import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/report_models.dart';
import 'report_preview_screen.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key, required this.clientId, this.caseId});
  final String clientId;
  final String? caseId;
  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<List<CaseReport>> data = load();
  Future<List<CaseReport>> load() =>
      repo.reportHistory(clientId: widget.clientId, caseId: widget.caseId);
  Future<void> open(CaseReport report) async {
    try {
      final bundle = await repo.readReport(report.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportPreviewScreen(repo: repo, stored: bundle),
        ),
      );
      if (mounted) setState(() => data = load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(workspaceError(e) ?? 'تعذر فتح التقرير.')),
        );
      }
    }
  }

  Future<void> history(CaseReport r) async {
    try {
      final attempts = await repo.shareHistory(r.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('سجل محاولات المشاركة'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (attempts.isEmpty)
                    const Text('لم تُسجل محاولات مشاركة؛ التقرير محفوظ فقط.'),
                  for (final a in attempts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        a.userConfirmedSentAt == null
                            ? shareStatusLabels[a.status]!
                            : 'أكد المستخدم الإرسال؛ الوصول غير مؤكد',
                      ),
                      subtitle: Text(
                        '${reportDate(a.createdAt)} ${a.createdAt.hour}:${a.createdAt.minute.toString().padLeft(2, '0')}\n${_channel(a.channel)} · ${a.format}\n${a.recipientSnapshot.isEmpty ? 'المستلم يختاره المستخدم خارجيًا' : a.recipientSnapshot}${a.actualTarget == null ? '' : '\nالوجهة التي أبلغ بها النظام: ${a.actualTarget}'}',
                      ),
                      trailing:
                          a.actorId == repo.staff.id &&
                              a.userConfirmedSentAt == null &&
                              ['OPENED', 'UNAVAILABLE'].contains(a.status)
                          ? IconButton(
                              tooltip: 'تأكيد الإرسال يدويًا',
                              icon: const Icon(Icons.task_alt),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: ctx,
                                  builder: (confirm) => AlertDialog(
                                    title: const Text(
                                      'هل أرسلت المستند بنفسك؟',
                                    ),
                                    content: const Text(
                                      'هذا إقرار منك بالإرسال، ولا يثبت وصول المستند أو قراءته.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(confirm, false),
                                        child: const Text('رجوع'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(confirm, true),
                                        child: const Text('نعم، أرسلته'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                try {
                                  await repo.confirmReportSent(a.id);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (_) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('تعذر تسجيل التأكيد.'),
                                      ),
                                    );
                                  }
                                }
                              },
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(workspaceError(e) ?? 'تعذر تحميل سجل المشاركة.'),
          ),
        );
      }
    }
  }

  String _channel(String c) =>
      const {
        'NATIVE': 'نافذة المشاركة',
        'WHATSAPP': 'واتساب مباشر',
        'WHATSAPP_WEB': 'واتساب ويب',
        'SAVE': 'حفظ ملف',
        'COPY': 'نسخ نص',
        'PRINT': 'طباعة',
      }[c] ??
      c;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التقارير وسجل المشاركة')),
    body: WorkspaceLoad(
      future: data,
      retry: () => setState(() => data = load()),
      buildData: (rows) => rows.isEmpty
          ? const Center(child: Text('لم تُحفظ تقارير بعد.'))
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final s = jsonDecode(r.snapshotJson) as Map<String, dynamic>;
                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(s['title'] as String),
                  subtitle: Text(
                    '${reportDate(r.createdAt)} · ${s['lawyerName']}\nمحفوظ${r.includesFinance ? ' · يتضمن بيانات مالية' : ''}',
                  ),
                  onTap: () => open(r),
                  trailing: IconButton(
                    tooltip: 'سجل المشاركة',
                    icon: const Icon(Icons.history),
                    onPressed: () => history(r),
                  ),
                );
              },
            ),
    ),
  );
}
