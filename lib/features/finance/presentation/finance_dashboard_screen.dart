import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_repository.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/finance_models.dart';
import '../data/installment_reminders.dart';
import 'finance_forms.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});
  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<FinanceDashboard> data = repo.financeDashboard();
  Map<String, String> names = {};
  void refresh() {
    if (mounted) setState(() => data = repo.financeDashboard());
  }

  Future<void> act(Future<void> Function() work) async {
    try {
      await work();
      refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(workspaceError(e) ?? 'تعذرت العملية.')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    repo
        .getLawyers()
        .then((rows) {
          if (mounted) {
            setState(() => names = {for (final r in rows) r.id: r.name});
          }
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الخزينة وحسابات الموكلين'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: WorkspaceLoad(
      future: data,
      retry: refresh,
      buildData: (d) {
        final outstanding = d.accounts.where((a) => a.balance > 0).toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        final months = d.monthlyNet.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ValueListenableBuilder<String>(
              valueListenable: InstallmentReminders.status,
              builder: (_, value, _) => Text(value),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => act(() async {
                    if (await InstallmentReminders.requestPermission()) {
                      await repo.enableInstallmentNotifications(true);
                    } else {
                      throw const FormatException(
                        'لم يُمنح إذن الإشعارات. راجع إعدادات الجهاز.',
                      );
                    }
                  }),
                  child: const Text('تفعيل تذكيرات الجهاز'),
                ),
                TextButton(
                  onPressed: () =>
                      act(() => repo.enableInstallmentNotifications(false)),
                  child: const Text('إيقاف تذكيرات الجهاز'),
                ),
              ],
            ),
            const Text(
              'حسابات الموكلين مستقلة عن مصروفات المكتب. صافي الحركة النقدية لا يمثل الربح ولا رصيد البنك الافتتاحي.',
            ),
            if (d.pendingLegacy > 0)
              Card(
                child: ListTile(
                  title: Text('${d.pendingLegacy} حركة قديمة بانتظار التصنيف'),
                  subtitle: const Text(
                    'لا تدخل الحركات غير المصنفة في الأرصدة الجديدة.',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/finance/legacy').then((_) {
                    refresh();
                  }),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _card('المقبوض من الموكلين', d.collected),
                _card('رد مبالغ', d.refunded),
                _card('تكاليف مدفوعة للموكلين', d.costs),
                _card('مصروفات المكتب', d.officeSpent),
                _card('صافي الحركة النقدية', d.cashMovement),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'أعمار المستحقات غير المسددة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'أيام التأخر من تاريخ الاستحقاق. الرصيد الدائن غير المخصص يظهر مستقلًا حتى تخصيصه.',
            ),
            Wrap(
              spacing: 12,
              children: [
                for (final e in d.aging(DateTime.now()).entries)
                  _card('${e.key} يوم', e.value),
              ],
            ),
            const Divider(),
            Text(
              'أكبر أرصدة مستحقة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (outstanding.isEmpty)
              const ListTile(title: Text('لا توجد أرصدة مستحقة.')),
            for (final a in outstanding.take(10))
              ListTile(
                title: Text(a.client.name),
                trailing: Text(moneyText(a.balance)),
                onTap: () =>
                    context.push('/client/${a.client.id}/account').then((_) {
                      refresh();
                    }),
              ),
            ExpansionTile(
              title: const Text('كل حسابات الموكلين'),
              children: [
                for (final a in d.accounts)
                  ListTile(
                    title: Text(a.client.name),
                    trailing: Text(moneyText(a.balance)),
                    onTap: () => context
                        .push('/client/${a.client.id}/account')
                        .then((_) {
                          refresh();
                        }),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('صافي التحصيل حسب المحامي المنسوب إليه القيد'),
              subtitle: const Text(
                'يتضمن دفعات الأتعاب والتكاليف؛ لا يمثل أتعابًا مكتسبة.',
              ),
              children: [
                for (final e in d.collectedByLawyer.entries)
                  ListTile(
                    title: Text(names[e.key] ?? 'محامٍ سابق'),
                    trailing: Text(moneyText(e.value)),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('صافي الحركة النقدية شهريًا'),
              children: [
                for (final e in months)
                  ListTile(
                    title: Text(e.key),
                    trailing: Text(moneyText(e.value)),
                  ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => act(() async {
                    await expenseDialog(context, repo);
                  }),
                  child: const Text('إضافة مصروف مكتب'),
                ),
                OutlinedButton(
                  onPressed: () => context.push('/finance/legacy').then((_) {
                    refresh();
                  }),
                  child: const Text('مراجعة المعاملات القديمة'),
                ),
              ],
            ),
            if (d.expenses.isEmpty)
              const ListTile(title: Text('لا توجد مصروفات مكتب مسجلة.')),
            for (final e in d.expenses)
              ListTile(
                title: Text(
                  '${e.description} — ${moneyText(e.amountMinor)}${e.voidedAt == null ? '' : ' — ملغى'}',
                ),
                subtitle: Text('${e.category} — ${financeDate(e.occurredAt)}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => act(() async {
                    if (value == 'history') {
                      await financialHistoryDialog(
                        context,
                        repo,
                        'OFFICE_EXPENSE',
                        e.id,
                      );
                    } else if (value == 'edit') {
                      await expenseDialog(context, repo, entry: e);
                    } else {
                      await financeReasonDialog(context, 'إلغاء مصروف المكتب', (
                        reason,
                      ) async {
                        await repo.saveOfficeExpense(
                          id: e.id,
                          expectedRevision: e.revision,
                          amountMinor: e.amountMinor,
                          description: e.description,
                          category: e.category,
                          paymentMethod: e.paymentMethod,
                          occurredAt: e.occurredAt,
                          reason: reason,
                          operationKey: e.operationKey,
                          voidEntry: true,
                        );
                      });
                    }
                  }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'history',
                      child: Text('سجل التغييرات'),
                    ),
                    if (e.voidedAt == null)
                      const PopupMenuItem(value: 'edit', child: Text('تصحيح')),
                    if (e.voidedAt == null)
                      const PopupMenuItem(
                        value: 'void',
                        child: Text('إلغاء المصروف'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
  Widget _card(String label, int value) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(label),
            Text(
              moneyText(value),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
