import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
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
      // The background color matches the dark blue hex #2e49a0 found in your JSON file[cite: 3]
      backgroundColor: const Color(0xFF2E49A0), 
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