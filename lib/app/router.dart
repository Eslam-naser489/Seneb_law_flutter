import 'package:go_router/go_router.dart';

import 'package:seneb_law/features/dashboard/presentation/dashboard_screen.dart';
import 'package:seneb_law/features/splash/presentation/splash_screen.dart';

import 'package:seneb_law/features/clients/presentation/screens/clients_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/add_client_screen.dart';

import 'package:seneb_law/features/cases/presentation/screens/cases_screen.dart';
import 'package:seneb_law/features/cases/presentation/screens/add_case_screen.dart';

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

    // ==================== الجلسات ====================
    GoRoute(
      path: '/add-session',
      builder: (context, state) => const AddSessionScreen(),
    ),
  ],
);