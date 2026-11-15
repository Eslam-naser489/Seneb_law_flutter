import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/finance_models.dart';
import 'finance_forms.dart';
import '../../reports/domain/report_models.dart';
import '../../reports/data/report_pdf.dart';
import '../../reports/presentation/report_preview_screen.dart';

class ClientAccountScreen extends StatefulWidget {
  const ClientAccountScreen({super.key, required this.clientId, this.caseId});
  final String clientId;
  final String? caseId;
  @override
  State<ClientAccountScreen> createState() => _ClientAccountScreenState();
}

class _ClientAccountScreenState extends State<ClientAccountScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<ClientAccount> data = repo.clientAccount(widget.clientId);
  bool busy = false;
  void refresh() {
    if (mounted) {
      setState(() => data = repo.clientAccount(widget.clientId));
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
      if (mounted) refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(workspaceError(e) ?? 'تعذرت العملية. أعد المحاولة.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receipt(ClientLedgerEntry e) async {
    final issued = await repo.issueReceipt(e.id);
    await previewReceipt(issued.number);
  }

  Future<void> previewReceipt(int number) async {
    final current = await repo.readReceipt(number);
    final entry = (await repo.clientAccount(widget.clientId)).entries.firstWhere((e) => e.id == current.entryId);
    final prepared = await repo.prepareReport(ReportRequest(clientId: widget.clientId, caseId: entry.caseId, kind: 'RECEIPT', receiptNumber: number));
    final bytes = await ReportPdf.build(prepared);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(repo: repo, prepared: prepared, pdf: bytes),
      ),
    );
  }

  Future<void> statement(ClientAccount a) async {
    final from = TextEditingController(),
        through = TextEditingController(text: financeDate(DateTime.now()));
    DateTime? start, end;
    try {
      final ok = await financeForm(
        context,
        title: 'فترة كشف الحساب',
        saveLabel: 'معاينة',
        fields: {
          'من YYYY-MM-DD؛ اتركه فارغًا للبداية': from,
          'حتى YYYY-MM-DD': through,
        },
        save: () async {
          start = from.text.trim().isEmpty ? null : parseFinanceDate(from.text);
          end = parseFinanceDate(through.text);
          if (start != null && start!.isAfter(end!)) {
            throw const FormatException('بداية الفترة بعد نهايتها.');
          }
        },
      );
      if (!ok) return;
    } finally {
      from.dispose();
      through.dispose();
    }
    final prepared = await repo.prepareReport(ReportRequest(clientId: widget.clientId, kind: 'STATEMENT', from: start, through: end));
    final bytes = await ReportPdf.build(prepared);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(repo: repo, prepared: prepared, pdf: bytes),
      ),
    );
  }

  Future<void> history(ClientLedgerEntry e) =>
      financialHistoryDialog(context, repo, 'LEDGER', e.id);

  Future<void> accrue(FeeAgreement a) async {
    final minutes = TextEditingController(),
        description = TextEditingController(),
        due = TextEditingController(text: financeDate(DateTime.now()));
    final key = const Uuid().v4();
    try {
      await financeForm(
        context,
        title: 'إثبات عمل بالساعة',
        fields: {
          'دقائق العمل': minutes,
          'وصف العمل': description,
          'الاستحقاق YYYY-MM-DD': due,
        },
        save: () async {
          final value = int.tryParse(minutes.text);
          if (value == null) {
            throw const FormatException('أدخل الدقائق بالأرقام 0–9.');
          }
          await repo.accrueHours(
            a.id,
            value,
            description.text,
            parseFinanceDate(due.text),
            key,
          );
        },
      );
    } finally {
      minutes.dispose();
      description.dispose();
      due.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('حساب الموكل'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: WorkspaceLoad(
      future: data,
      retry: refresh,
      buildData: (a) => DefaultTabController(
        length: 5,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    a.client.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${a.balance < 0 ? 'رصيد لصالح الموكل' : 'المستحق على الموكل'}: ${moneyText(a.balance.abs())}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('رصيد سداد غير مخصص: ${moneyText(a.unappliedCredit)}'),
                  Wrap(
                    spacing: 16,
                    children: [
                      for (final c in a.cases)
                        Text(
                          'القضية ${c.caseNumber}: ${moneyText(a.caseBalance(c.id))}',
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await ledgerDialog(
                                  context,
                                  repo,
                                  a,
                                  initialCaseId: widget.caseId,
                                );
                              }),
                        child: const Text('إضافة حركة'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await agreementDialog(
                                  context,
                                  repo,
                                  a,
                                  initialCaseId: widget.caseId,
                                );
                              }),
                        child: const Text('اتفاق أتعاب'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await allocationDialog(context, repo, a);
                              }),
                        child: const Text('تخصيص سداد'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => run(() => statement(a)),
                        child: const Text('كشف حساب PDF'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'الحركات'),
                Tab(text: 'الأقساط'),
                Tab(text: 'الاتفاقات'),
                Tab(text: 'التخصيصات'),
                Tab(text: 'الإيصالات'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _list(
                    a.entries.reversed
                        .map(
                          (e) => Card(
                            child: ListTile(
                              title: Text(
                                '${ledgerLabels[e.kind]} — ${moneyText(e.amountMinor)}${e.voidedAt == null ? '' : ' — ملغاة'}',
                              ),
                              subtitle: Text(
                                '${e.description}\n${financeDate(e.occurredAt)}${e.voidReason == null ? '' : '\n${e.voidReason}'}',
                              ),
                              trailing: PopupMenuButton<String>(
                                enabled: !busy,
                                onSelected: (action) => run(() async {
                                  if (action == 'history') {
                                    await history(e);
                                  }
                                  if (action == 'edit' && context.mounted) {
                                    await ledgerDialog(
                                      context,
                                      repo,
                                      a,
                                      entry: e,
                                    );
                                  }
                                  if (action == 'receipt') {
                                    await receipt(e);
                                  }
                                  if (action == 'void' && context.mounted) {
                                    await financeReasonDialog(
                                      context,
                                      'إلغاء الحركة وإيصالها',
                                      (reason) => repo.changeLedger(
                                        e.id,
                                        expectedRevision: e.revision,
                                        amountMinor: e.amountMinor,
                                        description: e.description,
                                        occurredAt: e.occurredAt,
                                        paymentMethod: e.paymentMethod,
                                        dueAt: e.dueAt,
                                        reason: reason,
                                        voidEntry: true,
                                      ),
                                    );
                                  }
                                }),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'history',
                                    child: Text('سجل التغييرات'),
                                  ),
                                  if (e.voidedAt == null) ...[
                                    if (e.agreementId == null ||
                                        a.agreements.any(
                                          (g) =>
                                              g.id == e.agreementId &&
                                              g.kind == 'HOURLY',
                                        ))
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('تصحيح'),
                                      ),
                                    if (e.agreementId == null ||
                                        a.agreements.any(
                                          (g) =>
                                              g.id == e.agreementId &&
                                              g.kind == 'HOURLY',
                                        ))
                                      const PopupMenuItem(
                                        value: 'void',
                                        child: Text('إلغاء الحركة'),
                                      ),
                                    if (['PAYMENT', 'REFUND'].contains(e.kind))
                                      const PopupMenuItem(
                                        value: 'receipt',
                                        child: Text('إصدار / عرض الإيصال'),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    'لا توجد حركات مالية. أضف اتفاق أتعاب أو دفعة.',
                  ),
                  _list([
                    const ListTile(
                      title: Text('التذكيرات محلية'),
                      subtitle: Text(
                        'يظهر التنبيه قبل الاستحقاق حسب الأيام المحددة. لا تُرسل رسائل للموكل تلقائيًا.',
                      ),
                    ),
                    for (final i in a.installments)
                      ListTile(
                        trailing: i.voidedAt != null
                            ? null
                            : IconButton(
                                tooltip: 'إعادة جدولة القسط',
                                icon: const Icon(Icons.edit_calendar_outlined),
                                onPressed: busy
                                    ? null
                                    : () => run(() async {
                                        await installmentDialog(
                                          context,
                                          repo,
                                          i,
                                        );
                                      }),
                              ),
                        title: Text(
                          '${i.label} — ${moneyText(i.amountMinor)}${i.voidedAt == null ? '' : ' — ملغى'}',
                        ),
                        subtitle: Text(
                          'الاستحقاق ${financeDate(i.dueAt)} — المتبقي ${moneyText(a.installmentRemaining(i))}',
                        ),
                        leading: Icon(
                          i.voidedAt != null || a.installmentRemaining(i) == 0
                              ? Icons.check_circle_outline
                              : DateTime.now().isAfter(
                                  i.dueAt.subtract(
                                    Duration(days: i.reminderDays),
                                  ),
                                )
                              ? Icons.notifications_active
                              : Icons.schedule,
                        ),
                      ),
                  ], 'لا توجد أقساط.'),
                  _list(
                    a.agreements
                        .map(
                          (g) => ListTile(
                            title: Text(
                              '${agreementLabels[g.kind]} — ${moneyText(g.amountMinor)}${g.kind == 'HOURLY' ? ' / ساعة' : ''}${g.voidedAt == null ? '' : ' — ملغى'}',
                            ),
                            subtitle: Text(g.terms),
                            trailing: g.voidedAt != null
                                ? null
                                : PopupMenuButton<String>(
                                    enabled: !busy,
                                    onSelected: (value) => run(() async {
                                      if (value == 'hours') {
                                        await accrue(g);
                                      } else {
                                        await financeReasonDialog(
                                          context,
                                          'إلغاء الاتفاق وأتعابه وأقساطه',
                                          (reason) =>
                                              repo.voidAgreement(g.id, reason),
                                        );
                                      }
                                    }),
                                    itemBuilder: (_) => [
                                      if (g.kind == 'HOURLY')
                                        const PopupMenuItem(
                                          value: 'hours',
                                          child: Text('إثبات عمل'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'void',
                                        child: Text('إلغاء لتصحيح الاتفاق'),
                                      ),
                                    ],
                                  ),
                          ),
                        )
                        .toList(),
                    'لا يوجد اتفاق أتعاب.',
                  ),
                  _list(
                    a.allocations
                        .map(
                          (allocation) => ListTile(
                            title: Text(
                              '${moneyText(allocation.amountMinor)}${allocation.voidedAt == null ? '' : ' — ملغى'}',
                            ),
                            subtitle: Text(
                              allocation.installmentId == null
                                  ? 'تخصيص لمستحق'
                                  : 'تخصيص لقسط',
                            ),
                            trailing: allocation.voidedAt != null
                                ? null
                                : IconButton(
                                    tooltip: 'إلغاء التخصيص',
                                    onPressed: busy
                                        ? null
                                        : () => run(() async {
                                            await financeReasonDialog(
                                              context,
                                              'إلغاء تخصيص السداد',
                                              (reason) => repo.voidAllocation(
                                                allocation.id,
                                                reason,
                                              ),
                                            );
                                          }),
                                    icon: const Icon(Icons.undo),
                                  ),
                          ),
                        )
                        .toList(),
                    'لا توجد تخصيصات. الدفعة غير المخصصة لا تُسدد قسطًا بعينه.',
                  ),
                  _list(
                    a.receipts
                        .map(
                          (r) => ListTile(
                            title: Text(
                              'إيصال رقم ${r.number}${r.voidedAt == null ? '' : ' — ملغى'}',
                            ),
                            subtitle: Text(financeDate(r.createdAt)),
                            onTap: busy
                                ? null
                                : () => run(() => previewReceipt(r.number)),
                          ),
                        )
                        .toList(),
                    'لم تصدر إيصالات. اختر دفعة ثم إصدار إيصال.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _list(List<Widget> children, String empty) => children.isEmpty
      ? Center(child: Text(empty, textAlign: TextAlign.center))
      : ListView(padding: const EdgeInsets.all(12), children: children);
}
