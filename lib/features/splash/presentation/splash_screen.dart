import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/app/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.startup = false});
  final bool startup;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.startup) _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // Wait for 3 seconds for the Lottie animation to play
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Center(
        child: Lottie.asset(
          'assets/lottie/splash.json',
          width: 400,
          height: 400,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
