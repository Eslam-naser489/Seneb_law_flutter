import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/core/utils/pdf_helper.dart'; // الجديد
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_cubit.dart';
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_state.dart';
import 'package:seneb_law/l10n/app_localizations.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // جلب بيانات النهارده وبكرة
    context.read<SessionsCubit>().loadDashboardSessions();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dashboardTitle)),
      body: Column(
        children: [
          // أزرار التنقل السريعة
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => context.push('/clients'),
                    icon: const Icon(Icons.people),
                    label: const Text('الموكلين'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/cases'),
                    icon: const Icon(Icons.gavel),
                    label: const Text('القضايا'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/add-session'),
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('جلسة جديدة'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/treasury'),
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('الخزينة'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),

          Expanded(
            child: BlocBuilder<SessionsCubit, SessionsState>(
              builder: (context, state) {
                if (state is SessionsLoading) return const Center(child: CircularProgressIndicator());
                if (state is SessionsError) return Center(child: Text('خطأ: ${state.message}'));

                if (state is SessionsLoaded) {
                  return ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      // قسم تنبيهات الغد (يظهر فقط إذا كان هناك جلسات غداً)
                      if (state.tomorrowSessions.isNotEmpty) ...[
                        const Text('🔔 تنبيه: جلسات الغد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                        const SizedBox(height: 8),
                        ...state.tomorrowSessions.map((item) => Card(
                          color: Colors.red.shade50,
                          shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.red, width: 1), borderRadius: BorderRadius.circular(8)),
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
                            title: Text('موكل: ${item.client.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('قضية: ${item.caseEntity.caseNumber}\nمحكمة: ${item.session.courtLocation}'),
                            isThreeLine: true,
                          ),
                        )),
                        const Divider(height: 32, thickness: 2),
                      ],

                      // قسم جلسات اليوم
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('⚖️ أجندة جلسات اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          // زرار الطباعة الجديد
                          if (state.todaySessions.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await PdfHelper.printDailyAgenda(
                                  state.todaySessions,
                                  'أجندة جلسات اليوم',
                                  DateTime.now(),
                                );
                              },
                              icon: const Icon(Icons.print),
                              label: const Text('طباعة الأجندة'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (state.todaySessions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: Text('لا توجد جلسات مسجلة لليوم. عطلة سعيدة! ⚖️', style: TextStyle(fontSize: 16))),
                        )
                      else
                        ...state.todaySessions.map((item) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: Color(0xFF2E49A0), child: Icon(Icons.gavel, color: Colors.white)),
                            title: Text('موكل: ${item.client.name}'),
                            subtitle: Text('قضية: ${item.caseEntity.caseNumber}\nمحكمة: ${item.session.courtLocation}'),
                            isThreeLine: true,
                          ),
                        )),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}