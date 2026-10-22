import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:seneb_law/app/router.dart';
import 'package:seneb_law/app/theme/app_theme.dart';
import 'package:seneb_law/l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SenebLawApp());
}

class SenebLawApp extends StatelessWidget {
  const SenebLawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // تحديد اللغة العربية كلغة أساسية وإجبارية للتطبيق
      locale: const Locale('ar'), 
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}