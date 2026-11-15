import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../../core/money/money.dart';
import '../../shared/presentation/async_save_dialog.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/finance_models.dart';

String financeDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime parseFinanceDate(String text) {
  final date = DateTime.tryParse(text.trim());
  if (date == null || financeDate(date) != text.trim()) {
    throw const FormatException('أدخل التاريخ بصيغة YYYY-MM-DD.');
  }
  return date;
}

Widget financeChoice(
  String label,
  String value,
  Map<String, String> choices,
  ValueChanged<String> update,
) => DropdownButtonFormField<String>(
  key: ValueKey('$label/$value'),
  initialValue: value,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: choices.entries
      .map(
        (e) => DropdownMenuItem(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
      )
      .toList(),
  onChanged: (value) {
    if (value != null) update(value);
  },
);

Future<bool> financeForm(
  BuildContext context, {
  required String title,
  required Map<String, TextEditingController> fields,
  Widget? extra,
  Set<String> multilineFields = const {},
  required Future<void> Function() save,
  String saveLabel = 'حفظ',
}) async =>
    await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: title,
        saveLabel: saveLabel,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?extra,
              for (final f in fields.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 10),
                  child: TextField(
                    controller: f.value,
                    minLines: multilineFields.contains(f.key) ? 3 : 1,
                    maxLines: multilineFields.contains(f.key) ? 6 : 1,
                    decoration: InputDecoration(labelText: f.key),
                  ),
                ),
            ],
          ),
        ),
        validate: () => null,
        errorMessage: workspaceError,
        onSave: () async {
          await save();
          return true;
        },
      ),
    ) ==
    true;

Future<bool> financeReasonDialog(
  BuildContext context,
  String title,
  Future<void> Function(String) action,
) async {
  final reason = TextEditingController();
  try {
    return await financeForm(
      context,
      title: title,
      fields: {'سبب التغيير': reason},
      save: () => action(reason.text),
    );
  } finally {
    reason.dispose();
  }
}

Future<bool> ledgerDialog(
  BuildContext context,
  ScopedAppRepository repo,
  ClientAccount account, {
  ClientLedgerEntry? entry,
  String? initialCaseId,
  String? initialKind,
  Future<void> Function(LedgerInput)? submit,
  String? initialAmount,
  String? initialDescription,
  DateTime? initialDate,
}) async {
  final lawyers = entry == null && repo.isOwner
      ? await repo.getLawyers()
      : <OfficeLawyerEntity>[];
  if (!context.mounted) return false;
  final amount = TextEditingController(
    text: entry == null
        ? initialAmount
        : Money.fromMinor(entry.amountMinor).toDecimalString(),
  );
  final description = TextEditingController(
    text: entry?.description ?? initialDescription,
  );
  final date = TextEditingController(
    text: financeDate(entry?.occurredAt ?? initialDate ?? DateTime.now()),
  );
  final due = TextEditingController(
    text: entry?.dueAt == null ? '' : financeDate(entry!.dueAt!),
  );
  final reason = TextEditingController();
  var kind = entry?.kind ?? initialKind ?? 'PAYMENT';
  var method = entry?.paymentMethod ?? 'CASH';
  var caseId = entry?.caseId ?? initialCaseId ?? '';
  var attributedLawyer = repo.staff.id;
  final key = const Uuid().v4();
  try {
    return await financeForm(
      context,
      title: entry == null ? 'إضافة حركة لحساب الموكل' : 'تصحيح حركة مالية',
      fields: {
        'المبلغ بالجنيه؛ التسوية تقبل السالب': amount,
        'البيان': description,
        'تاريخ الحركة YYYY-MM-DD': date,
        'تاريخ الاستحقاق الاختياري YYYY-MM-DD': due,
        if (entry != null) 'سبب التصحيح': reason,
      },
      extra: StatefulBuilder(
        builder: (context, update) => Column(
          children: [
            Text(account.client.name),
            if (entry == null && repo.isOwner)
              financeChoice('المحامي المنسوب إليه التحصيل', attributedLawyer, {
                for (final lawyer in lawyers) lawyer.id: lawyer.name,
              }, (value) => update(() => attributedLawyer = value)),
            if (entry == null)
              financeChoice(
                'نوع الحركة',
                kind,
                ledgerLabels,
                (v) => update(() => kind = v),
              ),
            if (entry == null)
              financeChoice('القضية', caseId, {
                '': 'حساب الموكل العام',
                for (final c in account.cases) c.id: c.caseNumber,
              }, (v) => update(() => caseId = v)),
            financeChoice(
              'طريقة الدفع',
              method,
              methodLabels,
              (v) => update(() => method = v),
            ),
            const Text(
              'الأتعاب والمصروفات تزيد المستحق، والدفعات والخصومات تخفضه. رد المبلغ يزيد المستحق. لا يسدد القسط حتى تخصيص الدفعة له.',
            ),
          ],
        ),
      ),
      save: () async {
        final input = LedgerInput(
          clientId: account.client.id,
          caseId: caseId.isEmpty ? null : caseId,
          kind: kind,
          amountMinor: Money.parse(amount.text).amountMinor,
          description: description.text,
          attributedLawyerId: attributedLawyer,
          occurredAt: parseFinanceDate(date.text),
          dueAt: due.text.trim().isEmpty ? null : parseFinanceDate(due.text),
          paymentMethod: ['PAYMENT', 'REFUND', 'EXPENSE_ADVANCE'].contains(kind)
              ? method
              : null,
        );
        if (submit != null) {
          await submit(input);
        } else if (entry == null) {
          await repo.postLedger(input, operationKey: key);
        } else {
          await repo.changeLedger(
            entry.id,
            expectedRevision: entry.revision,
            amountMinor: input.amountMinor,
            description: input.description,
            occurredAt: input.occurredAt,
            paymentMethod: input.paymentMethod,
            dueAt: input.dueAt,
            reason: reason.text,
          );
        }
      },
    );
  } finally {
    for (final c in [amount, description, date, due, reason]) {
      c.dispose();
    }
  }
}

Future<bool> installmentDialog(
  BuildContext context,
  ScopedAppRepository repo,
  Installment installment,
) async {
  final label = TextEditingController(text: installment.label),
      due = TextEditingController(text: financeDate(installment.dueAt)),
      days = TextEditingController(text: '${installment.reminderDays}'),
      reason = TextEditingController();
  try {
    return await financeForm(
      context,
      title: 'إعادة جدولة القسط',
      fields: {
        'الاسم': label,
        'الاستحقاق YYYY-MM-DD': due,
        'التذكير قبل الاستحقاق بالأيام': days,
        'سبب التغيير': reason,
      },
      save: () async {
        final reminder = int.tryParse(days.text.trim());
        if (reminder == null) {
          throw const FormatException('أدخل عدد أيام صحيحًا من 0 إلى 30.');
        }
        await repo.rescheduleInstallment(
          installment.id,
          expectedRevision: installment.revision,
          label: label.text,
          dueAt: parseFinanceDate(due.text),
          reminderDays: reminder,
          reason: reason.text,
        );
      },
    );
  } finally {
    for (final c in [label, due, days, reason]) {
      c.dispose();
    }
  }
}

Future<void> financialHistoryDialog(
  BuildContext context,
  ScopedAppRepository repo,
  String entityType,
  String id,
) async {
  final rows = await repo.financialHistory(entityType, id);
  final people = {
    for (final person in await repo.getLawyers()) person.id: person.name,
  };
  if (!context.mounted) return;
  String details(String? json) {
    if (json == null) return 'لا يوجد';
    final data = jsonDecode(json) as Map<String, dynamic>;
    final fields = {
      'amountMinor': 'المبلغ',
      'description': 'البيان',
      'category': 'الفئة',
      'label': 'اسم القسط',
      'kind': 'النوع',
      'paymentMethod': 'طريقة الدفع',
      'occurredAt': 'تاريخ الحركة',
      'dueAt': 'الاستحقاق',
      'voidedAt': 'تاريخ الإلغاء',
      'voidReason': 'سبب الإلغاء',
      'reminderDays': 'أيام التذكير',
      'revision': 'المراجعة',
    };
    return fields.entries
        .where((f) => data[f.key] != null)
        .map((f) {
          final value = data[f.key];
          final display = f.key == 'amountMinor'
              ? moneyText(value as int)
              : f.key == 'paymentMethod'
              ? methodLabels[value] ?? value
              : f.key == 'kind'
              ? ledgerLabels[value] ?? value
              : f.key.endsWith('At')
              ? financeDate(DateTime.fromMillisecondsSinceEpoch(value as int))
              : value;
          return '${f.value}: $display';
        })
        .join('\n');
  }

  const actions = {
    'CREATE': 'تسجيل',
    'EDIT': 'تصحيح',
    'VOID': 'إلغاء',
    'RESCHEDULE': 'إعادة جدولة',
    'ISSUE': 'إصدار',
  };
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('سجل التغييرات'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final row in rows)
              ListTile(
                title: Text(
                  '${actions[row.action] ?? row.action} — ${row.reason}',
                ),
                subtitle: SelectableText(
                  '${financeDate(row.createdAt)} — المستخدم: ${people[row.actorId] ?? row.actorId ?? 'النظام'}\nقبل:\n${details(row.beforeJson)}\nبعد:\n${details(row.afterJson)}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

Future<bool> agreementDialog(
  BuildContext context,
  ScopedAppRepository repo,
  ClientAccount account, {
  String? initialCaseId,
}) async {
  if (account.cases.isEmpty) return false;
  final amount = TextEditingController(), terms = TextEditingController();
  final schedule = TextEditingController(
    text: '${financeDate(DateTime.now())} | 0.00 | القسط الأول',
  );
  final reminders = TextEditingController(text: '1');
  var kind = 'FIXED', caseId = initialCaseId ?? account.cases.first.id;
  final key = const Uuid().v4();
  try {
    return await financeForm(
      context,
      title: 'اتفاق أتعاب',
      multilineFields: const {
        'الأقساط؛ سطر لكل قسط: YYYY-MM-DD | المبلغ | الاسم',
      },
      fields: {
        'الإجمالي أو سعر الساعة بالجنيه': amount,
        'شروط الاتفاق': terms,
        'الأقساط؛ سطر لكل قسط: YYYY-MM-DD | المبلغ | الاسم': schedule,
        'التذكير قبل الاستحقاق بعدد أيام (٠–٣٠)': reminders,
      },
      extra: StatefulBuilder(
        builder: (context, update) => Column(
          children: [
            financeChoice('القضية', caseId, {
              for (final c in account.cases) c.id: c.caseNumber,
            }, (v) => update(() => caseId = v)),
            financeChoice(
              'نوع الاتفاق',
              kind,
              agreementLabels,
              (v) => update(() => kind = v),
            ),
            const Text(
              'اتفاق الساعة لا ينشئ دينًا حتى إثبات العمل. الأقساط لا تكرر قيد الأتعاب. أتعاب النجاح والنسبة تحتاج تحققًا قانونيًا ولم تُفعّل.',
            ),
          ],
        ),
      ),
      save: () async {
        final items = <InstallmentInput>[];
        if (kind != 'HOURLY') {
          final days = int.tryParse(reminders.text.trim());
          if (days == null) {
            throw const FormatException('أدخل أيام التذكير بالأرقام 0–30.');
          }
          for (final line
              in schedule.text.split('\n').where((l) => l.trim().isNotEmpty)) {
            final parts = line.split('|').map((v) => v.trim()).toList();
            if (parts.length != 3) {
              throw const FormatException(
                'كل قسط يحتاج تاريخًا ومبلغًا واسمًا تفصلها |',
              );
            }
            items.add(
              InstallmentInput(
                parts[2],
                Money.parse(parts[1]).amountMinor,
                parseFinanceDate(parts[0]),
                reminderDays: days,
              ),
            );
          }
        }
        await repo.createAgreement(
          caseId: caseId,
          kind: kind,
          amountMinor: Money.parse(amount.text).amountMinor,
          terms: terms.text,
          schedule: items,
          operationKey: key,
        );
      },
    );
  } finally {
    for (final c in [amount, terms, schedule, reminders]) {
      c.dispose();
    }
  }
}

Future<bool> allocationDialog(
  BuildContext context,
  ScopedAppRepository repo,
  ClientAccount account,
) async {
  final credits = account.entries
      .where(
        (e) => isCredit(e) && e.amountMinor.abs() > account.allocated(e.id),
      )
      .toList();
  final charges = account.entries
      .where((e) => isCharge(e) && e.amountMinor > account.allocated(e.id))
      .toList();
  if (credits.isEmpty || charges.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يلزم رصيد غير مخصص ومستحق غير مسدد.')),
    );
    return false;
  }
  var payment = credits.first.id, charge = charges.first.id, installment = '';
  final amount = TextEditingController(),
      reason = TextEditingController(text: 'تخصيص سداد');
  final key = const Uuid().v4();
  try {
    return await financeForm(
      context,
      title: 'تخصيص دفعة أو خصم',
      fields: {'المبلغ بالجنيه': amount, 'سبب التخصيص': reason},
      extra: StatefulBuilder(
        builder: (context, update) => Column(
          children: [
            financeChoice('الدفعة أو الرصيد', payment, {
              for (final e in credits)
                e.id:
                    '${e.description} (${moneyText(e.amountMinor.abs() - account.allocated(e.id))})',
            }, (v) => update(() => payment = v)),
            financeChoice(
              'المستحق',
              charge,
              {
                for (final e in charges)
                  e.id:
                      '${e.description} (${moneyText(e.amountMinor - account.allocated(e.id))})',
              },
              (v) => update(() {
                charge = v;
                installment = '';
              }),
            ),
            financeChoice('القسط', installment, {
              '': 'دون قسط',
              for (final i in account.installments.where(
                (i) => i.chargeId == charge && i.voidedAt == null,
              ))
                i.id:
                    '${i.label} (${moneyText(account.installmentRemaining(i))})',
            }, (v) => update(() => installment = v)),
          ],
        ),
      ),
      save: () async {
        await repo.allocatePayment(
          paymentId: payment,
          chargeId: charge,
          installmentId: installment.isEmpty ? null : installment,
          amountMinor: Money.parse(amount.text).amountMinor,
          reason: reason.text,
          operationKey: key,
        );
      },
    );
  } finally {
    amount.dispose();
    reason.dispose();
  }
}

Future<bool> expenseDialog(
  BuildContext context,
  ScopedAppRepository repo, {
  OfficeExpense? entry,
  Future<void> Function(int, String, String, String, DateTime, String)? submit,
  String? initialAmount,
  String? initialDescription,
  DateTime? initialDate,
}) async {
  final amount = TextEditingController(
    text: entry == null
        ? initialAmount
        : Money.fromMinor(entry.amountMinor).toDecimalString(),
  );
  final description = TextEditingController(
        text: entry?.description ?? initialDescription,
      ),
      category = TextEditingController(text: entry?.category);
  final reason = TextEditingController(),
      date = TextEditingController(
        text: financeDate(entry?.occurredAt ?? initialDate ?? DateTime.now()),
      );
  var method = entry?.paymentMethod ?? 'CASH';
  final key = const Uuid().v4();
  try {
    return await financeForm(
      context,
      title: entry == null ? 'مصروف مكتب مستقل' : 'تصحيح مصروف مكتب',
      fields: {
        'المبلغ بالجنيه': amount,
        'البيان': description,
        'الفئة (إيجار، رواتب، ...)': category,
        'التاريخ YYYY-MM-DD': date,
        'سبب التسجيل أو التصحيح': reason,
      },
      extra: StatefulBuilder(
        builder: (context, update) => financeChoice(
          'طريقة الدفع',
          method,
          methodLabels,
          (v) => update(() => method = v),
        ),
      ),
      save: () async {
        final value = Money.parse(amount.text).amountMinor;
        if (submit != null) {
          await submit(
            value,
            category.text,
            method,
            reason.text,
            parseFinanceDate(date.text),
            description.text,
          );
        } else {
          await repo.saveOfficeExpense(
            id: entry?.id,
            expectedRevision: entry?.revision,
            amountMinor: value,
            description: description.text,
            category: category.text,
            paymentMethod: method,
            occurredAt: parseFinanceDate(date.text),
            reason: reason.text,
            operationKey: key,
          );
        }
      },
    );
  } finally {
    for (final c in [amount, description, category, reason, date]) {
      c.dispose();
    }
  }
}
