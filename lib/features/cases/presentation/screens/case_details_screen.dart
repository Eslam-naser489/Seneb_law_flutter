import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/features/shared/presentation/async_save_dialog.dart';
import 'package:seneb_law/features/shared/presentation/legacy_treasury_notice.dart';
import '../cubit/case_details_cubit.dart';
import '../cubit/case_details_state.dart';

// المكتبات الجديدة
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

class CaseDetailsScreen extends StatefulWidget {
  final CaseWithClient caseWithClient;

  const CaseDetailsScreen({super.key, required this.caseWithClient});

  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen> {
  static const _statusLabels = {
    'ACTIVE': 'جارية',
    'CLOSED': 'منتهية',
    'ON_HOLD': 'موقوفة',
    'ARCHIVED': 'مؤرشفة',
  };
  late String _statusLabel;

  @override
  void initState() {
    super.initState();
    _statusLabel =
        _statusLabels[widget.caseWithClient.caseEntity.statusCode] ??
        widget.caseWithClient.caseEntity.status;
  }

  Future<void> _showAddNoteDialog(
    BuildContext context,
    CaseDetailsCubit cubit,
  ) async {
    final controller = TextEditingController();
    await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: 'إضافة ملاحظة جديدة',
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'اكتب تفاصيل الملاحظة أو التطورات...',
            border: OutlineInputBorder(),
          ),
        ),
        validate: () =>
            controller.text.trim().isEmpty ? 'اكتب الملاحظة أولًا.' : null,
        onSave: () => cubit.addCaseNote(
          widget.caseWithClient.caseEntity.id,
          controller.text.trim(),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showAddPaymentDialog(
    BuildContext context,
    CaseDetailsCubit cubit,
  ) async {
    final amountController = TextEditingController();
    final titleController = TextEditingController(text: 'دفعة أتعاب');
    await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: 'إضافة دفعة أتعاب',
        saveLabel: 'حفظ الدفعة',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'البيان',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ (ج.م)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        validate: () {
          final amount = double.tryParse(amountController.text);
          if (amount == null || !amount.isFinite || amount <= 0) {
            return 'أدخل مبلغًا صحيحًا أكبر من صفر.';
          }
          if (titleController.text.trim().isEmpty) return 'اكتب البيان أولًا.';
          return null;
        },
        onSave: () => cubit.addCasePayment(
          caseId: widget.caseWithClient.caseEntity.id,
          clientId: widget.caseWithClient.client.id,
          title: titleController.text.trim(),
          amount: double.parse(amountController.text),
        ),
      ),
    );
    amountController.dispose();
    titleController.dispose();
  }

  Future<void> _pickAndSaveDocument(
    BuildContext context,
    CaseDetailsCubit cubit,
  ) async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null ||
          file.path == null ||
          !context.mounted ||
          cubit.isClosed) {
        return;
      }
      final controller = TextEditingController();
      await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: 'تسمية المستند',
          saveLabel: 'حفظ في الأرشيف',
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'مثال: صورة التوكيل، حافظة مستندات',
            ),
          ),
          validate: () =>
              controller.text.trim().isEmpty ? 'اكتب اسم المستند أولًا.' : null,
          onSave: () => cubit.addDocument(
            caseId: widget.caseWithClient.caseEntity.id,
            title: controller.text.trim(),
            filePath: file.path!,
            fileType: file.extension?.toLowerCase() ?? 'unknown',
          ),
        ),
      );
      controller.dispose();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار المستند. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _showStatusDialog(BuildContext context) async {
    final controller = TextEditingController();
    var code =
        _statusLabels.entries
            .where((entry) => entry.value == _statusLabel)
            .firstOrNull
            ?.key ??
        'ACTIVE';
    final saved = await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: 'تحديث حالة القضية',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (context, update) => DropdownButtonFormField<String>(
                initialValue: code,
                decoration: const InputDecoration(labelText: 'حالة القضية'),
                items: _statusLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) update(() => code = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'سبب التغيير'),
            ),
          ],
        ),
        validate: () =>
            controller.text.trim().isEmpty ? 'اكتب سبب التغيير.' : null,
        onSave: () async {
          await context.read<AppRepository>().updateCaseStatus(
            widget.caseWithClient.caseEntity.id,
            code,
            reason: controller.text.trim(),
          );
          return true;
        },
      ),
    );
    if (saved == true && mounted) {
      setState(() => _statusLabel = _statusLabels[code]!);
    }
    controller.dispose();
  }

  Future<void> _showDecisionDialog(
    BuildContext context,
    CaseDetailsCubit cubit,
    SessionEntity session,
  ) async {
    final decision = TextEditingController(text: session.decision);
    final reason = TextEditingController();
    await showAsyncSaveDialog(
      context: context,
      builder: (_) => AsyncSaveDialog(
        title: 'تحديث قرار الجلسة',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: decision,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'قرار الجلسة'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'سبب التغيير'),
            ),
          ],
        ),
        validate: () => reason.text.trim().isEmpty ? 'اكتب سبب التغيير.' : null,
        onSave: () async {
          await context.read<AppRepository>().updateSessionDecision(
            session.id,
            decision.text.trim(),
            reason: reason.text.trim(),
          );
          await cubit.loadCaseDetails(widget.caseWithClient.caseEntity.id);
          return true;
        },
      ),
    );
    decision.dispose();
    reason.dispose();
  }

  Future<void> _openDocument(BuildContext context, String path) async {
    try {
      final resolved = await context.read<AppRepository>().resolveDocumentPath(
        path,
      );
      final result = await OpenFilex.open(resolved);
      if (!context.mounted || result.type == ResultType.done) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح الملف. تحقق من توفره ومن البرنامج المناسب.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح الملف. تحقق من توفره ثم حاول مرة أخرى.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final workspace = repo is ScopedAppRepository ? repo : null;
    final finance = workspace?.canReadFinance ?? true;
    final editable = workspace?.canEdit ?? true;
    return BlocProvider(
      create: (context) =>
          CaseDetailsCubit(repo)
            ..loadCaseDetails(widget.caseWithClient.caseEntity.id),
      child: Builder(
        builder: (context) {
          final cubit = context.read<CaseDetailsCubit>();
          return DefaultTabController(
            length: finance ? 4 : 3,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  'قضية: ${widget.caseWithClient.caseEntity.caseNumber}',
                ),
                actions: [
                  if(workspace != null && finance)
                    IconButton(tooltip:'قوالب Word والمستندات',icon:const Icon(Icons.description_outlined),onPressed:()=>context.push('/templates?client=${Uri.encodeComponent(widget.caseWithClient.client.id)}&case=${Uri.encodeComponent(widget.caseWithClient.caseEntity.id)}')),
                  if (workspace != null && workspace.canEdit) ...[
                    IconButton(tooltip: 'إرسال تقرير للموكل', icon: const Icon(Icons.send_outlined),
                      onPressed: () => context.push('/case/${Uri.encodeComponent(widget.caseWithClient.caseEntity.id)}/report')),
                    IconButton(tooltip: 'التقارير وسجل المشاركة', icon: const Icon(Icons.history),
                      onPressed: () => context.push('/case/${Uri.encodeComponent(widget.caseWithClient.caseEntity.id)}/reports')),
                  ],
                  if (workspace != null && finance)
                    IconButton(
                      tooltip: 'حساب الموكل والأتعاب',
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      onPressed: () => context.push(
                        '/client/${widget.caseWithClient.client.id}/account?case=${widget.caseWithClient.caseEntity.id}',
                      ),
                    ),
                  if (workspace != null)
                    IconButton(
                      tooltip: 'إدارة الإسناد',
                      icon: const Icon(Icons.groups_outlined),
                      onPressed: () => context.push(
                        '/case/${Uri.encodeComponent(widget.caseWithClient.caseEntity.id)}/assignments',
                      ),
                    ),
                  if (workspace != null)
                    IconButton(
                      tooltip: 'ملف الموكل',
                      icon: const Icon(Icons.person_outline),
                      onPressed: () => context.push(
                        '/client/${Uri.encodeComponent(widget.caseWithClient.client.id)}',
                      ),
                    ),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الموكل: ${widget.caseWithClient.client.name}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'الخصم: ${widget.caseWithClient.caseEntity.opponentName ?? "غير مسجل"}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'الحالة: $_statusLabel',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (editable)
                              TextButton.icon(
                                onPressed: () => _showStatusDialog(context),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('تحديث الحالة'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: BlocBuilder<CaseDetailsCubit, CaseDetailsState>(
                        builder: (context, state) {
                          if (state is CaseDetailsLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (state is CaseDetailsError) {
                            return Center(child: Text('خطأ: ${state.message}'));
                          }
                          if (state is CaseDetailsLoaded) {
                            final totalPaid = state.transactions
                                .where((item) => item.type == 'INCOME')
                                .fold(0.0, (sum, item) => sum + item.amount);

                            return Column(
                              children: [
                                TabBar(
                                  isScrollable: true,
                                  tabs: [
                                    const Tab(
                                      icon: Icon(Icons.note),
                                      text: 'الملاحظات',
                                    ),
                                    const Tab(
                                      icon: Icon(Icons.calendar_month),
                                      text: 'الجلسات',
                                    ),
                                    if (finance)
                                      const Tab(
                                        icon: Icon(Icons.attach_money),
                                        text: 'الماليات',
                                      ),
                                    const Tab(
                                      icon: Icon(Icons.folder_special),
                                      text: 'الأرشيف',
                                    ), // التبويب الجديد
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      // 1. الملاحظات
                                      state.notes.isEmpty
                                          ? const Center(
                                              child: Text('لا توجد ملاحظات.'),
                                            )
                                          : ListView.builder(
                                              itemCount: state.notes.length,
                                              itemBuilder: (c, i) => Card(
                                                child: ListTile(
                                                  title: Text(
                                                    state.notes[i].content,
                                                  ),
                                                  subtitle: Text(
                                                    '${state.notes[i].createdAt.year}-${state.notes[i].createdAt.month}-${state.notes[i].createdAt.day}',
                                                  ),
                                                ),
                                              ),
                                            ),
                                      // 2. الجلسات
                                      state.sessions.isEmpty
                                          ? const Center(
                                              child: Text('لا توجد جلسات.'),
                                            )
                                          : ListView.builder(
                                              itemCount: state.sessions.length,
                                              itemBuilder: (c, i) => Card(
                                                child: ListTile(
                                                  leading: const Icon(
                                                    Icons.event_available,
                                                  ),
                                                  title: Text(
                                                    'المحكمة: ${state.sessions[i].courtLocation}',
                                                  ),
                                                  subtitle: Text(
                                                    '${state.sessions[i].sessionDate.year}-${state.sessions[i].sessionDate.month}-${state.sessions[i].sessionDate.day}\nالدائرة: ${state.sessions[i].circleNumber ?? "غير مسجلة"}\nالقرار: ${state.sessions[i].decision ?? "غير مسجل"}',
                                                  ),
                                                  trailing: !editable
                                                      ? null
                                                      : IconButton(
                                                          tooltip:
                                                              'تحديث قرار الجلسة',
                                                          icon: const Icon(
                                                            Icons.edit_outlined,
                                                          ),
                                                          onPressed: () =>
                                                              _showDecisionDialog(
                                                                context,
                                                                cubit,
                                                                state
                                                                    .sessions[i],
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                      // 3. الماليات
                                      if (finance)
                                        Column(
                                          children: [
                                            if (!repo.canPostLegacyTransactions)
                                              const LegacyTreasuryNotice(),
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Wrap(
                                                spacing: 12,
                                                runSpacing: 8,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    repo.canPostLegacyTransactions
                                                        ? 'إجمالي المدفوع: $totalPaid ج.م'
                                                        : 'إجمالي المقبوضات القديمة: $totalPaid ج.م',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.green,
                                                    ),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        !repo
                                                            .canPostLegacyTransactions
                                                        ? null
                                                        : () =>
                                                              _showAddPaymentDialog(
                                                                context,
                                                                cubit,
                                                              ),
                                                    icon: const Icon(Icons.add),
                                                    label: const Text(
                                                      'دفعة جديدة',
                                                    ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Divider(),
                                            Expanded(
                                              child: state.transactions.isEmpty
                                                  ? const Center(
                                                      child: Text(
                                                        'لم يتم تسجيل أي دفعات.',
                                                      ),
                                                    )
                                                  : ListView.builder(
                                                      itemCount: state
                                                          .transactions
                                                          .length,
                                                      itemBuilder: (c, i) {
                                                        final transaction = state
                                                            .transactions[i];
                                                        final isIncome =
                                                            transaction.type ==
                                                            'INCOME';
                                                        final color = isIncome
                                                            ? Colors.green
                                                            : Colors.red;
                                                        return Card(
                                                          child: ListTile(
                                                            leading: Icon(
                                                              Icons
                                                                  .monetization_on,
                                                              color: color,
                                                            ),
                                                            title: Text(
                                                              transaction.title,
                                                            ),
                                                            subtitle: Text(
                                                              '${transaction.transactionDate.year}-${transaction.transactionDate.month}-${transaction.transactionDate.day}',
                                                            ),
                                                            trailing: Text(
                                                              '${isIncome ? '+' : '-'}${transaction.amount} ج.م',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: color,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                            ),
                                          ],
                                        ),
                                      // 4. الأرشيف (الجديد)
                                      Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  _pickAndSaveDocument(
                                                    context,
                                                    cubit,
                                                  ),
                                              icon: const Icon(
                                                Icons.upload_file,
                                              ),
                                              label: const Text(
                                                'رفع مستند جديد',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFF2E49A0,
                                                ),
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: state.documents.isEmpty
                                                ? const Center(
                                                    child: Text(
                                                      'الأرشيف فارغ. قم برفع المستندات والتوكيلات.',
                                                    ),
                                                  )
                                                : ListView.builder(
                                                    itemCount:
                                                        state.documents.length,
                                                    itemBuilder: (context, index) {
                                                      final doc = state
                                                          .documents[index];
                                                      return Card(
                                                        child: ListTile(
                                                          leading: Icon(
                                                            doc.fileType ==
                                                                    'pdf'
                                                                ? Icons
                                                                      .picture_as_pdf
                                                                : Icons.image,
                                                            color:
                                                                doc.fileType ==
                                                                    'pdf'
                                                                ? Colors.red
                                                                : Colors.blue,
                                                            size: 32,
                                                          ),
                                                          title: Text(
                                                            doc.title,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                          subtitle: Text(
                                                            'تاريخ الرفع: ${doc.uploadedAt.year}-${doc.uploadedAt.month}-${doc.uploadedAt.day}',
                                                          ),
                                                          trailing: IconButton(
                                                            icon: const Icon(
                                                              Icons.open_in_new,
                                                              color:
                                                                  Colors.grey,
                                                            ),
                                                            tooltip:
                                                                'فتح الملف',
                                                            onPressed: () =>
                                                                _openDocument(
                                                                  context,
                                                                  doc.filePath,
                                                                ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: !editable
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _showAddNoteDialog(context, cubit),
                      icon: const Icon(Icons.add_comment),
                      label: const Text('ملاحظة'),
                    ),
            ),
          );
        },
      ),
    );
  }
}
