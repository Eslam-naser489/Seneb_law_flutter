import 'package:go_router/go_router.dart';
import 'package:seneb_law/features/dashboard/presentation/dashboard_screen.dart';
import 'package:seneb_law/features/splash/presentation/splash_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/clients_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/add_client_screen.dart';
// الوارد الجديد
import 'package:seneb_law/features/cases/presentation/screens/cases_screen.dart';
import 'package:seneb_law/features/cases/presentation/screens/add_case_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
    GoRoute(path: '/clients', builder: (context, state) => const ClientsScreen()),
    GoRoute(path: '/add-client', builder: (context, state) => const AddClientScreen()),
    // راوت القضايا
    GoRoute(path: '/cases', builder: (context, state) => const CasesScreen()),
    GoRoute(path: '/add-case', builder: (context, state) => const AddCaseScreen()),
  ],
);