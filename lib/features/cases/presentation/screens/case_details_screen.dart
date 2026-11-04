import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
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
  void _showAddNoteDialog(BuildContext context, CaseDetailsCubit cubit) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إضافة ملاحظة جديدة'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب تفاصيل الملاحظة أو التطورات...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (noteController.text.trim().isNotEmpty) {
                  cubit.addCaseNote(
                    widget.caseWithClient.caseEntity.id,
                    noteController.text.trim(),
                  );
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _showAddPaymentDialog(BuildContext context, CaseDetailsCubit cubit) {
    final amountController = TextEditingController();
    final titleController = TextEditingController(text: 'دفعة أتعاب');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إضافة دفعة أتعاب'),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount.isFinite &&
                    amount > 0 &&
                    titleController.text.trim().isNotEmpty) {
                  cubit.addCasePayment(
                    caseId: widget.caseWithClient.caseEntity.id,
                    clientId: widget.caseWithClient.client.id,
                    title: titleController.text.trim(),
                    amount: amount,
                  );
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('حفظ الدفعة'),
            ),
          ],
        );
      },
    );
  }

  // الجديد: دالة اختيار ورفع الملفات
  Future<void> _pickAndSaveDocument(
    BuildContext context,
    CaseDetailsCubit cubit,
  ) async {
    try {
      final file = await FilePicker.pickFile();

      if (file != null && file.path != null) {
        final path = file.path!;
        final ext = file.extension?.toLowerCase() ?? 'unknown';

        if (!context.mounted || cubit.isClosed) return;

        final titleController = TextEditingController();
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تسمية المستند'),
            content: TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'مثال: صورة التوكيل، حافظة مستندات',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    cubit.addDocument(
                      caseId: widget.caseWithClient.caseEntity.id,
                      title: titleController.text.trim(),
                      filePath: path,
                      fileType: ext,
                    );
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('حفظ في الأرشيف'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر اختيار المستند: $error')));
    }
  }

  Future<void> _openDocument(BuildContext context, String path) async {
    try {
      final result = await OpenFilex.open(path);
      if (!context.mounted || result.type == ResultType.done) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح الملف: ${result.message}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر فتح الملف: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return BlocProvider(
      create: (context) =>
          CaseDetailsCubit(repo)
            ..loadCaseDetails(widget.caseWithClient.caseEntity.id),
      child: Builder(
        builder: (context) {
          final cubit = context.read<CaseDetailsCubit>();
          return DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  'قضية: ${widget.caseWithClient.caseEntity.caseNumber}',
                ),
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
                              'الحالة: ${widget.caseWithClient.caseEntity.status}',
                              style: const TextStyle(fontSize: 16),
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
                                const TabBar(
                                  isScrollable: true,
                                  tabs: [
                                    Tab(
                                      icon: Icon(Icons.note),
                                      text: 'الملاحظات',
                                    ),
                                    Tab(
                                      icon: Icon(Icons.calendar_month),
                                      text: 'الجلسات',
                                    ),
                                    Tab(
                                      icon: Icon(Icons.attach_money),
                                      text: 'الماليات',
                                    ),
                                    Tab(
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
                                                    '${state.sessions[i].sessionDate.year}-${state.sessions[i].sessionDate.month}-${state.sessions[i].sessionDate.day}',
                                                  ),
                                                ),
                                              ),
                                            ),
                                      // 3. الماليات
                                      Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Wrap(
                                              spacing: 12,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  'إجمالي المدفوع: $totalPaid ج.م',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                ElevatedButton.icon(
                                                  onPressed: () =>
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
                                                      final transaction =
                                                          state.transactions[i];
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
              floatingActionButton: FloatingActionButton.extended(
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
