import 'package:flutter/material.dart';
import 'package:seneb_law/l10n/app_localizations.dart';


class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
      ),
      body: Center(
        child: Text(
          'مرحباً بك في ${l10n.appTitle}\nلوحة التحكم قيد الإنشاء...',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}