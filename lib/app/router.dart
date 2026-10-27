import 'package:go_router/go_router.dart';
import 'package:seneb_law/features/dashboard/presentation/dashboard_screen.dart';
import 'package:seneb_law/features/splash/presentation/splash_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/clients_screen.dart';
import 'package:seneb_law/features/clients/presentation/screens/add_client_screen.dart'; // مسار الشاشة الجديدة

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/clients',
      builder: (context, state) => const ClientsScreen(),
    ),
    GoRoute( // الراوت الجديد
      path: '/add-client',
      builder: (context, state) => const AddClientScreen(),
    ),
  ],
);