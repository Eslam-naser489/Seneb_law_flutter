import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
    // جلب جلسات اليوم عند فتح التطبيق
    context.read<SessionsCubit>().loadTodaySessions();
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
                  // زرار الخزينة الجديد
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
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('جلسات اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          // عرض الأجندة
          Expanded(
            child: BlocBuilder<SessionsCubit, SessionsState>(
              builder: (context, state) {
                if (state is SessionsLoading) return const Center(child: CircularProgressIndicator());
                if (state is SessionsError) return Center(child: Text('خطأ: ${state.message}'));
                if (state is SessionsLoaded) {
                  if (state.todaySessions.isEmpty) {
                    return const Center(child: Text('لا توجد جلسات مسجلة لليوم. عطلة سعيدة! ⚖️', style: TextStyle(fontSize: 16)));
                  }
                  return ListView.builder(
                    itemCount: state.todaySessions.length,
                    itemBuilder: (context, index) {
                      final item = state.todaySessions[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.warning, color: Colors.white)),
                          title: Text('موكل: ${item.client.name}'),
                          subtitle: Text('قضية: ${item.caseEntity.caseNumber}\nمحكمة: ${item.session.courtLocation}'),
                          isThreeLine: true,
                        ),
                      );
                    },
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