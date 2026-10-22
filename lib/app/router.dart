import 'package:go_router/go_router.dart';
import 'package:seneb_law/features/dashboard/presentation/dashboard_screen.dart';
import 'package:seneb_law/features/splash/presentation/splash_screen.dart';

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
  ],
);