import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/database/app_repository.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/cases/presentation/screens/add_case_screen.dart';
import '../features/cases/presentation/screens/case_details_screen.dart';
import '../features/cases/presentation/screens/cases_screen.dart';
import '../features/clients/presentation/screens/add_client_screen.dart';
import '../features/clients/presentation/screens/client_profile_screen.dart';
import '../features/clients/presentation/screens/clients_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/lawyers/presentation/assignment_screen.dart';
import '../features/lawyers/presentation/team_screen.dart';
import '../features/search/presentation/global_search_screen.dart';
import '../features/sessions/presentation/screens/add_session_screen.dart';
import '../features/shared/presentation/workspace_load.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/treasury/presentation/screens/treasury_screen.dart';
import '../features/finance/presentation/client_account_screen.dart';
import '../features/finance/presentation/finance_dashboard_screen.dart';
import '../features/finance/presentation/legacy_review_screen.dart';
import '../features/reports/presentation/report_composer_screen.dart';
import '../features/reports/presentation/report_history_screen.dart';

GoRouter createAppRouter({
  ScopedAppRepository? workspace,
  VoidCallback? onLock,
}) => GoRouter(
  initialLocation: workspace == null ? '/' : '/dashboard',
  overridePlatformDefaultLocation: true,
  redirect: (_, state) {
    if (workspace == null) return null;
    final path = state.uri.path;
    if (!workspace.isOwner &&
        (path == '/backup' ||
            path == '/treasury' ||
            path == '/team' ||
            path.startsWith('/finance/') ||
            path.startsWith('/team/'))) {
      return '/access-denied';
    }
    if (!workspace.canEdit &&
        ['/add-client', '/add-case', '/add-session'].contains(path)) {
      return '/access-denied';
    }
    return null;
  },
  errorBuilder: (_, _) =>
      const Scaffold(body: Center(child: Text('الصفحة غير متاحة.'))),
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
    GoRoute(
      path: '/dashboard',
      builder: (_, _) => DashboardScreen(workspace: workspace, onLock: onLock),
    ),
    GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
    GoRoute(path: '/clients', builder: (_, _) => const ClientsScreen()),
    GoRoute(path: '/add-client', builder: (_, _) => const AddClientScreen()),
    GoRoute(path: '/cases', builder: (_, _) => const CasesScreen()),
    GoRoute(
      path: '/add-case',
      builder: (_, state) =>
          AddCaseScreen(clientId: state.uri.queryParameters['client']),
    ),
    GoRoute(path: '/add-session', builder: (_, _) => const AddSessionScreen()),
    GoRoute(
      path: '/treasury',
      builder: (_, _) => workspace == null
          ? const TreasuryScreen()
          : const FinanceDashboardScreen(),
    ),
    if (workspace == null)
      GoRoute(
        path: '/case-details',
        builder: (_, state) {
          final record = state.extra;
          return record is CaseWithClient
              ? CaseDetailsScreen(caseWithClient: record)
              : const Scaffold(body: Center(child: Text('القضية غير متاحة.')));
        },
      ),
    if (workspace != null) ...[
      GoRoute(
        path: '/finance/legacy',
        builder: (_, _) => const LegacyReviewScreen(),
      ),
      GoRoute(
        path: '/access-denied',
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('الصلاحيات')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ليس لديك صلاحية لفتح هذه الصفحة.'),
                TextButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('العودة للأجندة'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(path: '/search', builder: (_, _) => const GlobalSearchScreen()),
      GoRoute(
        path: '/team',
        builder: (_, _) => const TeamScreen(),
        routes: [
          GoRoute(
            path: ':id/workload',
            builder: (_, state) =>
                WorkloadScreen(staffId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/client/:id',
        builder: (_, state) =>
            ClientProfileScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'account',
            builder: (_, state) => ClientAccountScreen(
              clientId: state.pathParameters['id']!,
              caseId: state.uri.queryParameters['case'],
            ),
          ),
          GoRoute(path: 'reports', builder: (_, state) => ReportHistoryScreen(clientId: state.pathParameters['id']!)),
          GoRoute(
            path: 'assignments',
            builder: (_, state) => AssignmentScreen(
              recordId: state.pathParameters['id']!,
              forCase: false,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/case/:id',
        builder: (_, state) => _ScopedCaseScreen(
          key: ValueKey(state.pathParameters['id']),
          repo: workspace,
          id: state.pathParameters['id']!,
        ),
        routes: [
          GoRoute(path: 'report', builder: (_, state) => ReportComposerScreen(caseId: state.pathParameters['id']!)),
          GoRoute(path: 'reports', builder: (_, state) => _ScopedReportHistory(repo: workspace,caseId:state.pathParameters['id']!)),
          GoRoute(
            path: 'assignments',
            builder: (_, state) => AssignmentScreen(
              recordId: state.pathParameters['id']!,
              forCase: true,
            ),
          ),
        ],
      ),
    ],
  ],
);

class _ScopedReportHistory extends StatefulWidget {
  const _ScopedReportHistory({required this.repo,required this.caseId});
  final ScopedAppRepository repo;
  final String caseId;
  @override
  State<_ScopedReportHistory> createState()=>_ScopedReportHistoryState();
}
class _ScopedReportHistoryState extends State<_ScopedReportHistory> {
  late Future<CaseWithClient> data=widget.repo.caseDetails(widget.caseId);
  @override
  Widget build(BuildContext context)=>WorkspaceLoad(future:data,retry:()=>setState(()=>data=widget.repo.caseDetails(widget.caseId)),
    buildData:(value)=>ReportHistoryScreen(clientId:value.client.id,caseId:widget.caseId));
}

class _ScopedCaseScreen extends StatefulWidget {
  const _ScopedCaseScreen({super.key, required this.repo, required this.id});
  final ScopedAppRepository repo;
  final String id;
  @override
  State<_ScopedCaseScreen> createState() => _ScopedCaseScreenState();
}

class _ScopedCaseScreenState extends State<_ScopedCaseScreen> {
  late Future<CaseWithClient> _data = widget.repo.caseDetails(widget.id);

  @override
  Widget build(BuildContext context) => WorkspaceLoad(
    future: _data,
    retry: () => setState(() => _data = widget.repo.caseDetails(widget.id)),
    buildData: (data) => CaseDetailsScreen(caseWithClient: data),
  );
}
