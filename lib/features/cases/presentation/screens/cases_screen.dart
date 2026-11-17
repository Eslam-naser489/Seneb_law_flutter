import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/app/theme/app_colors.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';

import '../cubit/cases_cubit.dart';
import '../cubit/cases_state.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  bool _mine = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<CasesCubit>().loadCases();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'جارية':
      case 'ACTIVE':
        return AppColors.success;
      case 'موقوفة':
      case 'ON_HOLD':
        return AppColors.warning;
      case 'منتهية':
      case 'CLOSED':
        return AppColors.secondaryText;
      case 'مؤرشفة':
      case 'ARCHIVED':
        return const Color(0xFF6B7280);
      default:
        return AppColors.accentBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final workspace = repo is ScopedAppRepository ? repo : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إدارة القضايا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (workspace != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilterChip(
                label: const Text('قضاياي المسندة'),
                selected: _mine,
                selectedColor: Colors.white,
                checkmarkColor: AppColors.primaryNavy,
                labelStyle: TextStyle(
                  color: _mine ? AppColors.primaryNavy : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                side: BorderSide(
                  color: _mine ? Colors.white : Colors.white.withValues(alpha: 0.3),
                ),
                onSelected: (value) {
                  setState(() => _mine = value);
                  context.read<CasesCubit>().loadCases(mine: value);
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث برقم القضية أو اسم الموكل أو الخصم...',
                      hintStyle: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: AppColors.secondaryText),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20, color: AppColors.secondaryText),
                              onPressed: () {
                                _searchController.clear();
                                context.read<CasesCubit>().searchCases('');
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      context.read<CasesCubit>().searchCases(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Cases List
          Expanded(
            child: BlocBuilder<CasesCubit, CasesState>(
              builder: (context, state) {
                if (state is CasesLoading) {
                  return const AppLoadingIndicator(message: 'جارٍ تحميل القضايا...');
                }
                if (state is CasesError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text('حدث خطأ: ${state.message}'),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => context.read<CasesCubit>().loadCases(),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is CasesLoaded) {
                  if (state.cases.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: AppEmptyState(
                          icon: Icons.gavel_outlined,
                          title: 'لا توجد قضايا مطابقة للبحث',
                          subtitle: _searchController.text.isNotEmpty
                              ? 'تحقق من رقم القضية أو اسم الموكل وجرب مرة أخرى.'
                              : 'ابدأ بتسجيل أول قضية للمكتب.',
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: state.cases.length,
                    itemBuilder: (context, index) {
                      final caseItem = state.cases[index];
                      final status = caseItem.caseEntity.status;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            if (workspace == null) {
                              await context.push(
                                '/case-details',
                                extra: caseItem,
                              );
                            } else {
                              await context.push(
                                '/case/${Uri.encodeComponent(caseItem.caseEntity.id)}',
                              );
                            }
                            if (context.mounted) {
                              context.read<CasesCubit>().loadCases();
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppColors.primaryNavy.withValues(alpha: 0.08),
                                  child: const Icon(Icons.gavel, color: AppColors.primaryNavy, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'قضية: ${caseItem.caseEntity.caseNumber}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppColors.primaryText,
                                              ),
                                            ),
                                          ),
                                          AppStatusBadge(
                                            label: status,
                                            color: _getStatusColor(status),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.person_outline, size: 14, color: AppColors.secondaryText),
                                          const SizedBox(width: 4),
                                          Text(
                                            'الموكل: ${caseItem.client.name}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.primaryText,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(Icons.shield_outlined, size: 14, color: AppColors.secondaryText),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'الخصم: ${caseItem.caseEntity.opponentName ?? "غير مسجل"}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors.secondaryText,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.secondaryText),
                              ],
                            ),
                          ),
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
      floatingActionButton: workspace?.canEdit == false
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/add-case'),
              icon: const Icon(Icons.add),
              label: const Text('قضية جديدة', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
    );
  }
}
