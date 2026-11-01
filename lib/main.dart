import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/app/router.dart';
import 'package:seneb_law/app/theme/app_theme.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/features/clients/presentation/cubit/clients_cubit.dart';
import 'package:seneb_law/features/cases/presentation/cubit/cases_cubit.dart';
import 'package:seneb_law/l10n/app_localizations.dart'; // مسار جديد

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final repository = AppRepository(db);
  runApp(SenebLawApp(repository: repository));
}

class SenebLawApp extends StatelessWidget {
  final AppRepository repository;
  const SenebLawApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      // استخدمنا MultiBlocProvider عشان عندنا كذا كيوبت دلوقتي
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => ClientsCubit(repository)),
          BlocProvider(create: (context) => CasesCubit(repository)),
        ],
        child: MaterialApp.router(
          locale: const Locale('ar'), 
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          theme: AppTheme.lightTheme,
          routerConfig: appRouter,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}