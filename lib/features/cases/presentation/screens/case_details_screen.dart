import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import '../cubit/case_details_cubit.dart';
import '../cubit/case_details_state.dart';

class CaseDetailsScreen extends StatefulWidget {
  final CaseWithClient caseWithClient;

  const CaseDetailsScreen({super.key, required this.caseWithClient});

  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _showAddNoteDialog(BuildContext context, CaseDetailsCubit cubit) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إضافة ملاحظة جديدة'),
          content: TextField(
            controller: _noteController,
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
                if (_noteController.text.trim().isNotEmpty) {
                  cubit.addCaseNote(
                    widget.caseWithClient.caseEntity.id,
                    _noteController.text.trim(),
                  );
                  _noteController.clear();
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
                    labelText: 'البيان', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'المبلغ (ج.م)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount > 0 && titleController.text.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return BlocProvider(
      create: (context) => CaseDetailsCubit(repo)
        ..loadCaseDetails(widget.caseWithClient.caseEntity.id),
      child: Builder(
        builder: (context) {
          final cubit = context.read<CaseDetailsCubit>();
          return Scaffold(
            appBar: AppBar(
                title: Text(
                    'قضية: ${widget.caseWithClient.caseEntity.caseNumber}')),
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
                          Text('الموكل: ${widget.caseWithClient.client.name}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              'الخصم: ${widget.caseWithClient.caseEntity.opponentName ?? "غير مسجل"}',
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(
                              'الحالة: ${widget.caseWithClient.caseEntity.status}',
                              style: const TextStyle(fontSize: 16)),
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
                              child: CircularProgressIndicator());
                        }
                        if (state is CaseDetailsError) {
                          return Center(child: Text('خطأ: ${state.message}'));
                        }
                        if (state is CaseDetailsLoaded) {
                          // حساب إجمالي المدفوع في هذه القضية
                          final totalPaid = state.transactions
                              .fold(0.0, (sum, item) => sum + item.amount);

                          return DefaultTabController(
                            length: 3, // تم تغيير العدد لـ 3 تبويبات
                            child: Column(
                              children: [
                                const TabBar(
                                  tabs: [
                                    Tab(
                                        icon: Icon(Icons.note),
                                        text: 'الملاحظات'),
                                    Tab(
                                        icon: Icon(Icons.calendar_month),
                                        text: 'الجلسات'),
                                    Tab(
                                        icon: Icon(Icons.attach_money),
                                        text: 'الماليات'), // التبويب الجديد
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      // 1. قائمة الملاحظات
                                      state.notes.isEmpty
                                          ? const Center(
                                              child: Text('لا توجد ملاحظات.'))
                                          : ListView.builder(
                                              itemCount: state.notes.length,
                                              itemBuilder: (context, index) {
                                                final note = state.notes[index];
                                                return Card(
                                                    child: ListTile(
                                                        title:
                                                            Text(note.content),
                                                        subtitle: Text(
                                                            '${note.createdAt.year}-${note.createdAt.month}-${note.createdAt.day}')));
                                              },
                                            ),
                                      // 2. قائمة الجلسات
                                      state.sessions.isEmpty
                                          ? const Center(
                                              child:
                                                  Text('لا توجد جلسات مسجلة.'))
                                          : ListView.builder(
                                              itemCount: state.sessions.length,
                                              itemBuilder: (context, index) {
                                                final session =
                                                    state.sessions[index];
                                                return Card(
                                                    child: ListTile(
                                                        leading: const Icon(Icons
                                                            .event_available),
                                                        title: Text(
                                                            'المحكمة: ${session.courtLocation}'),
                                                        subtitle: Text(
                                                            '${session.sessionDate.year}-${session.sessionDate.month}-${session.sessionDate.day}')));
                                              },
                                            ),
                                      // 3. قائمة الماليات (الجديدة)
                                      Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                    'إجمالي المدفوع: $totalPaid ج.م',
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.green)),
                                                ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _showAddPaymentDialog(
                                                          context, cubit),
                                                  icon: const Icon(Icons.add),
                                                  label:
                                                      const Text('دفعة جديدة'),
                                                  style: ElevatedButton
                                                      .styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white),
                                                )
                                              ],
                                            ),
                                          ),
                                          const Divider(),
                                          Expanded(
                                            child: state.transactions.isEmpty
                                                ? const Center(
                                                    child: Text(
                                                        'لم يتم تسجيل أي دفعات.'))
                                                : ListView.builder(
                                                    itemCount:
                                                        state.transactions
                                                            .length,
                                                    itemBuilder:
                                                        (context, index) {
                                                      final t = state
                                                          .transactions[index];
                                                      return Card(
                                                        child: ListTile(
                                                          leading: const Icon(
                                                              Icons
                                                                  .monetization_on,
                                                              color:
                                                                  Colors.green),
                                                          title: Text(t.title),
                                                          subtitle: Text(
                                                              '${t.transactionDate.year}-${t.transactionDate.month}-${t.transactionDate.day}'),
                                                          trailing: Text(
                                                              '+${t.amount} ج.م',
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .green,
                                                                  fontSize:
                                                                      16)),
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
                            ),
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
          );
        },
      ),
    );
  }
}