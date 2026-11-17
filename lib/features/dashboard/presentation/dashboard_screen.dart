import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:seneb_law/app/theme/app_colors.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/utils/pdf_helper.dart';
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_cubit.dart';
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_state.dart';
import 'package:seneb_law/l10n/app_localizations.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.workspace, this.onLock});
  final ScopedAppRepository? workspace;
  final VoidCallback? onLock;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SessionsCubit>().loadDashboardSessions();
  }

  String _formatToday() {
    try {
      return DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.now());
    } catch (_) {
      final now = DateTime.now();
      return '${now.day}/${now.month}/${now.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final staffName = widget.workspace?.staff.name ?? 'المحامي';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.dashboardTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (widget.workspace != null) ...[
            IconButton(
              tooltip: 'البحث الموحد (Ctrl+K)',
              icon: const Icon(Icons.search),
              onPressed: () => context.push('/search'),
            ),
            PopupMenuButton<String>(
              tooltip: 'جلسة المستخدم',
              child: Container(
                margin: const EdgeInsetsDirectional.only(start: 6, end: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_circle_outlined, size: 20),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        staffName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              onSelected: (_) => widget.onLock?.call(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(staffName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const PopupMenuItem(
                  value: 'switch',
                  child: Row(
                    children: [
                      Icon(Icons.switch_account_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('تبديل المستخدم'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'lock',
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18),
                      SizedBox(width: 8),
                      Text('قفل البرنامج'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: BlocBuilder<SessionsCubit, SessionsState>(
        builder: (context, state) {
          if (state is SessionsLoading) {
            return const AppLoadingIndicator(message: 'جارٍ تحميل الأجندة...');
          }
          if (state is SessionsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('حدث خطأ: ${state.message}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.read<SessionsCubit>().loadDashboardSessions(),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          final todaySessions = state is SessionsLoaded ? state.todaySessions : [];
          final tomorrowSessions = state is SessionsLoaded ? state.tomorrowSessions : [];

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Hero Welcome Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryNavy, AppColors.secondaryNavy],
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F0A1F44),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.premiumGold.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.premiumGold.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Text(
                                  'مكتب سنيب للمحاماة',
                                  style: TextStyle(
                                    color: AppColors.lightGold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatToday(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'مرحباً بك، $staffName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            todaySessions.isEmpty
                                ? 'لا توجد جلسات مجدولة لليوم. تابع القضايا والمهام الجارية.'
                                : 'لديك ${todaySessions.length} جلسة مجدولة لليوم في المحاكم.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.balance,
                        size: 32,
                        color: AppColors.premiumGold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Quick Actions Bar
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الإجراءات والوصول السريع',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildQuickActionButton(
                            icon: Icons.people_outline,
                            label: 'الموكلين',
                            onTap: () => context.push('/clients'),
                            primary: true,
                          ),
                          const SizedBox(width: 8),
                          _buildQuickActionButton(
                            icon: Icons.gavel_outlined,
                            label: 'القضايا',
                            onTap: () => context.push('/cases'),
                            primary: true,
                          ),
                          const SizedBox(width: 8),
                          if (widget.workspace?.canEdit ?? true) ...[
                            _buildQuickActionButton(
                              icon: Icons.event_available_outlined,
                              label: 'جلسة جديدة',
                              onTap: () => context.push('/add-session'),
                              accent: true,
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (widget.workspace?.isOwner ?? true) ...[
                            _buildQuickActionButton(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'الخزينة والماليات',
                              onTap: () => context.push('/treasury'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (widget.workspace?.canEdit ?? false) ...[
                            _buildQuickActionButton(
                              icon: Icons.description_outlined,
                              label: 'قوالب Word',
                              onTap: () => context.push('/templates'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (widget.workspace?.isOwner ?? false) ...[
                            _buildQuickActionButton(
                              icon: Icons.groups_outlined,
                              label: 'فريق المكتب',
                              onTap: () => context.push('/team'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (widget.workspace?.isOwner ?? true)
                            _buildQuickActionButton(
                              icon: Icons.backup_outlined,
                              label: 'نسخ احتياطي',
                              onTap: () => context.push('/backup'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // KPI Stats Cards
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      title: 'جلسات اليوم',
                      count: todaySessions.length.toString(),
                      subtitle: 'جلسة في المحكمة',
                      icon: Icons.calendar_today_outlined,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'جلسات الغد',
                      count: tomorrowSessions.length.toString(),
                      subtitle: tomorrowSessions.isNotEmpty ? 'تنبيه استباقي' : 'لا جلسات غداً',
                      icon: Icons.notifications_active_outlined,
                      color: tomorrowSessions.isNotEmpty ? AppColors.warning : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Tomorrow Urgent Notice
              if (tomorrowSessions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'تنبيه مبكر: ${tomorrowSessions.length} جلسة غداً',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...tomorrowSessions.map(
                        (item) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFFEE2E2),
                                child: const Icon(Icons.gavel, size: 18, color: AppColors.error),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'الموكل: ${item.client.name}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.primaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'قضية: ${item.caseEntity.caseNumber} · محكمة: ${item.session.courtLocation}${item.session.circleNumber != null ? " · دائرة: ${item.session.circleNumber}" : ""}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Today's Agenda Section
              AppSectionHeader(
                title: 'أجندة جلسات اليوم',
                trailing: todaySessions.isNotEmpty
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          await PdfHelper.printDailyAgenda(
                            List.from(todaySessions),
                            'أجندة جلسات اليوم',
                            DateTime.now(),
                          );
                        },
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: const Text('طباعة الأجندة'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      )
                    : null,
              ),

              if (todaySessions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const AppEmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'لا توجد جلسات مسجلة لليوم.',
                    subtitle: 'جميع جلسات اليوم مكتملة أو لم تُحدد مواعيد بعد.',
                  ),
                )
              else
                ...todaySessions.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
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
                                        'الموكل: ${item.client.name}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.primaryText,
                                        ),
                                      ),
                                    ),
                                    AppStatusBadge(
                                      label: item.caseEntity.status,
                                      color: item.caseEntity.status == 'جارية' || item.caseEntity.status == 'ACTIVE'
                                          ? AppColors.success
                                          : AppColors.accentBlue,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'قضية: ${item.caseEntity.caseNumber} · محكمة: ${item.session.courtLocation}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                if (item.session.decision != null && item.session.decision!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'القرار: ${item.session.decision}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    bool accent = false,
  }) {
    Color bg;
    Color fg;
    Border? border;

    if (primary) {
      bg = AppColors.primaryNavy;
      fg = Colors.white;
      border = null;
    } else if (accent) {
      bg = AppColors.accentBlue;
      fg = Colors.white;
      border = null;
    } else {
      bg = AppColors.surface;
      fg = AppColors.primaryNavy;
      border = Border.all(color: const Color(0xFFE2E8F0));
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
