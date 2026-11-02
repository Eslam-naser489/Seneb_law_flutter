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
              title: Text('قضية: ${widget.caseWithClient.caseEntity.caseNumber}'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // كارت بيانات القضية والموكل
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
                                fontSize: 18, fontWeight: FontWeight.bold),
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
                              child: CircularProgressIndicator());
                        }
                        if (state is CaseDetailsError) {
                          return Center(child: Text('خطأ: ${state.message}'));
                        }
                        if (state is CaseDetailsLoaded) {
                          return DefaultTabController(
                            length: 2,
                            child: Column(
                              children: [
                                const TabBar(
                                  tabs: [
                                    Tab(
                                        icon: Icon(Icons.note),
                                        text: 'الملاحظات والتطورات'),
                                    Tab(
                                        icon: Icon(Icons.calendar_month),
                                        text: 'سجل الجلسات'),
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      // قائمة الملاحظات
                                      state.notes.isEmpty
                                          ? const Center(
                                              child: Text(
                                                  'لا توجد ملاحظات مدونة بعد.'))
                                          : ListView.builder(
                                              itemCount: state.notes.length,
                                              itemBuilder: (context, index) {
                                                final note = state.notes[index];
                                                return Card(
                                                  child: ListTile(
                                                    title: Text(note.content),
                                                    subtitle: Text(
                                                        'التاريخ: ${note.createdAt.year}-${note.createdAt.month}-${note.createdAt.day}'),
                                                  ),
                                                );
                                              },
                                            ),
                                      // قائمة الجلسات
                                      state.sessions.isEmpty
                                          ? const Center(
                                              child: Text(
                                                  'لا توجد جلسات مسجلة لهذه القضية.'))
                                          : ListView.builder(
                                              itemCount: state.sessions.length,
                                              itemBuilder: (context, index) {
                                                final session =
                                                    state.sessions[index];
                                                return Card(
                                                  child: ListTile(
                                                    leading: const Icon(
                                                        Icons.event_available),
                                                    title: Text(
                                                        'المحكمة: ${session.courtLocation}'),
                                                    subtitle: Text(
                                                        'التاريخ: ${session.sessionDate.year}-${session.sessionDate.month}-${session.sessionDate.day}'),
                                                  ),
                                                );
                                              },
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
              label: const Text('إضافة ملاحظة'),
            ),
          );
        },
      ),
    );
  }
}