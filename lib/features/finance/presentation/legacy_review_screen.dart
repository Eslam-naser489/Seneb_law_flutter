import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/money/money.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/finance_models.dart';
import 'finance_forms.dart';

class LegacyReviewScreen extends StatefulWidget {
  const LegacyReviewScreen({super.key});
  @override
  State<LegacyReviewScreen> createState() => _LegacyReviewScreenState();
}

class _LegacyReviewScreenState extends State<LegacyReviewScreen> {
  ScopedAppRepository get repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<List<LegacyReviewItem>> data = repo.legacyReviews();
  bool busy = false;
  void refresh() {
    if (mounted) setState(() => data = repo.legacyReviews());
  }

  Future<void> classify(LegacyReviewItem item, String target) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final review = item.review, source = item.source;
      final amount = review.proposedAmountMinor == null
          ? null
          : Money.fromMinor(review.proposedAmountMinor!).toDecimalString();
      if (target == 'EXCLUDE') {
        await financeReasonDialog(
          context,
          'استبعاد من الدفاتر مع حفظ الأصل',
          (reason) => repo.classifyLegacy(
            review.id,
            destination: 'EXCLUDE',
            reason: reason,
          ),
        );
      } else if (target == 'OFFICE') {
        await expenseDialog(
          context,
          repo,
          initialAmount: amount,
          initialDescription: source.title,
          initialDate: source.transactionDate,
          submit: (value, category, method, reason, date, description) =>
              repo.classifyLegacy(
                review.id,
                destination: 'OFFICE',
                reason: reason,
                amountMinor: value,
                category: category,
                paymentMethod: method,
                officeDescription: description,
                officeOccurredAt: date,
              ),
        );
      } else {
        final clients = (await repo.financeDashboard()).accounts;
        if (!mounted) return;
        if (clients.isEmpty) {
          throw const FormatException('أضف الموكل أولًا ثم صنّف الحركة.');
        }
        var clientId = clients.any((a) => a.client.id == source.clientId)
            ? source.clientId!
            : clients.first.client.id;
        final reason = TextEditingController();
        bool ok;
        try {
          ok = await financeForm(
            context,
            title: 'تأكيد موكل الحركة وسبب التصنيف',
            saveLabel: 'متابعة',
            fields: {'سبب التصنيف وتصحيح أي تعارض أو فرق تقريب': reason},
            extra: StatefulBuilder(
              builder: (context, update) => financeChoice('الموكل', clientId, {
                for (final a in clients) a.client.id: a.client.name,
              }, (v) => update(() => clientId = v)),
            ),
            save: () async {
              if (reason.text.trim().isEmpty) {
                throw const FormatException('يلزم سبب التصنيف.');
              }
            },
          );
          if (ok && mounted) {
            final account = clients.singleWhere((a) => a.client.id == clientId);
            await ledgerDialog(
              context,
              repo,
              account,
              initialAmount: amount,
              initialDescription: source.title,
              initialDate: source.transactionDate,
              initialKind: source.type == 'INCOME'
                  ? 'PAYMENT'
                  : 'EXPENSE_ADVANCE',
              initialCaseId: account.cases.any((c) => c.id == source.caseId)
                  ? source.caseId
                  : null,
              submit: (input) => repo.classifyLegacy(
                review.id,
                destination: 'LEDGER',
                reason: reason.text,
                ledger: input,
              ),
            );
          }
        } finally {
          reason.dispose();
        }
      }
      refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              workspaceError(e) ?? 'تعذر التصنيف. لم تُعتمد الحركة.',
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
    appBar: AppBar(title: const Text('مراجعة المعاملات القديمة')),
    body: WorkspaceLoad(
      future: data,
      retry: refresh,
      buildData: (rows) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'الأصل محفوظ دون تعديل. تأكد من الموكل والقضية والمبلغ والطبيعة المحاسبية قبل التصنيف. الاستبعاد يحتاج سببًا. التصنيف لا يصدر إيصالًا تلقائيًا.',
          ),
          Text(
            'الإجمالي ${rows.length} — قيد المراجعة ${rows.where((r) => r.classification == null).length} — مصنف ${rows.where((r) => r.classification?.destination != 'EXCLUDE' && r.classification != null).length} — مستبعد ${rows.where((r) => r.classification?.destination == 'EXCLUDE').length}',
          ),
          if (rows.isEmpty)
            const ListTile(title: Text('لا توجد معاملات قديمة للمراجعة.')),
          for (final item in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.source.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'الأصل ${item.review.sourceAmountText} جنيه — ${item.source.type == 'INCOME' ? 'وارد' : 'صادر'} — ${financeDate(item.source.transactionDate)}',
                    ),
                    Text(
                      'المقترح ${item.review.proposedAmountMinor == null ? 'غير قابل للتحويل' : moneyText(item.review.proposedAmountMinor!)} — فرق التقريب ${item.review.roundingResidual ?? 'غير معروف'} جنيه',
                    ),
                    if (item.review.ownershipMismatch)
                      const Text(
                        'تعارض بين موكل الحركة وموكل القضية؛ صحح الإسناد عند التصنيف.',
                      ),
                    if (item.review.isNegative ||
                        item.review.conversionError != null)
                      const Text(
                        'المبلغ يحتاج مراجعة خاصة. لا تعتمد الإشارة القديمة دون التحقق.',
                      ),
                    if (item.classification != null)
                      Text(
                        'تمت المراجعة: ${item.classification!.destination == 'EXCLUDE'
                            ? 'مستبعد'
                            : item.classification!.destination == 'OFFICE'
                            ? 'مصروف مكتب'
                            : 'حساب موكل'}\n${item.classification!.reason}',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => classify(item, 'LEDGER'),
                            child: const Text('حساب موكل'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => classify(item, 'OFFICE'),
                            child: const Text('مصروف مكتب'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => classify(item, 'EXCLUDE'),
                            child: const Text('استبعاد مع سبب'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
