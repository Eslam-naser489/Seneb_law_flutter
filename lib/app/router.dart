import 'package:go_router/go_router.dart';
import 'package:seneb_law/core/database/app_repository.dart';

import 'package:seneb_law/features/dashboard/presentation/dashboard_screen.dart';
import 'package:seneb_law/features/splash/presentation/splash_screen.dart';

import 'package:seneb_law/features/clients/presentation/screens/clients_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/add_client_screen.dart';

import 'package:seneb_law/features/cases/presentation/screens/cases_screen.dart';
import 'package:seneb_law/features/cases/presentation/screens/add_case_screen.dart';
import 'package:seneb_law/features/cases/presentation/screens/case_details_screen.dart';
import 'package:seneb_law/features/treasury/presentation/screens/treasury_screen.dart'; // إضافة السطر ده
// ==================== الجلسات ====================
import 'package:seneb_law/features/sessions/presentation/screens/add_session_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // ==================== الرئيسية ====================
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),

    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),

    // ==================== الموكلين ====================
    GoRoute(
      path: '/clients',
      builder: (context, state) => const ClientsScreen(),
    ),

    GoRoute(
      path: '/add-client',
      builder: (context, state) => const AddClientScreen(),
    ),

    // ==================== القضايا ====================
    GoRoute(
      path: '/cases',
      builder: (context, state) => const CasesScreen(),
    ),

    GoRoute(
      path: '/add-case',
      builder: (context, state) => const AddCaseScreen(),
    ),

    GoRoute(
      path: '/case-details',
      builder: (context, state) {
        final caseWithClient = state.extra as CaseWithClient;
        return CaseDetailsScreen(caseWithClient: caseWithClient);
      },
    ),

    // ==================== الجلسات ====================
    GoRoute(
      path: '/add-session',
      builder: (context, state) => const AddSessionScreen(),
    ),
    GoRoute(
  path: '/treasury',
  builder: (context, state) => const TreasuryScreen(),
),
  ],
);
