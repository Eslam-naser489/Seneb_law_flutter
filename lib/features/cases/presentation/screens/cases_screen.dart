import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubit/cases_cubit.dart';
import '../cubit/cases_state.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  @override
  void initState() {
    super.initState();
    context.read<CasesCubit>().loadCases();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة القضايا')),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ابحث برقم القضية أو اسم الموكل...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (value) {
                context.read<CasesCubit>().searchCases(value);
              },
            ),
          ),
          Expanded(
            child: BlocBuilder<CasesCubit, CasesState>(
              builder: (context, state) {
                if (state is CasesLoading) return const Center(child: CircularProgressIndicator());
                if (state is CasesError) return Center(child: Text('حدث خطأ: ${state.message}'));

                if (state is CasesLoaded) {
                  if (state.cases.isEmpty) {
                    return const Center(child: Text('لا توجد قضايا مطابقة للبحث.'));
                  }
                  return ListView.builder(
                    itemCount: state.cases.length,
                    itemBuilder: (context, index) {
                      final caseItem = state.cases[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          onTap: () => context.push('/case-details', extra: caseItem),
                          leading: const CircleAvatar(child: Icon(Icons.gavel)),
                          title: Text('قضية رقم: ${caseItem.caseEntity.caseNumber}'),
                          subtitle: Text('الموكل: ${caseItem.client.name}\nالخصم: ${caseItem.caseEntity.opponentName ?? "غير مسجل"}'),
                          isThreeLine: true,
                          trailing: Chip(label: Text(caseItem.caseEntity.status)),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-case'),
        icon: const Icon(Icons.add),
        label: const Text('قضية جديدة'),
      ),
    );
  }
}
