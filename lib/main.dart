import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:seneb_law/app/router.dart';
import 'package:seneb_law/features/treasury/presentation/cubit/treasury_cubit.dart';
import 'package:seneb_law/app/theme/app_theme.dart';
import 'package:seneb_law/features/lawyers/presentation/office_gate.dart';

import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/features/finance/data/installment_reminders.dart';

import 'package:seneb_law/features/clients/presentation/cubit/clients_cubit.dart';
import 'package:seneb_law/features/cases/presentation/cubit/cases_cubit.dart';
import 'package:seneb_law/features/sessions/presentation/cubit/sessions_cubit.dart';

import 'package:seneb_law/l10n/app_localizations.dart';

RandomAccessFile? _instanceLease;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final repository = AppRepository(db);

  try {
    final root = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'seneb_law'),
    );
    await root.create(recursive: true);
    if (_instanceLease == null) {
      final lease = await File(
        p.join(root.path, 'instance.lock'),
      ).open(mode: FileMode.append);
      try {
        await lease.lock(FileLock.exclusive);
        _instanceLease = lease;
      } catch (_) {
        await lease.close();
        rethrow;
      }
    }
    await repository.initialize();
    final access = OfficeAccess(repository);
    InstallmentReminders(db).start();
    runApp(
      OfficeGate(
        access: access,
        workspace: (scoped) =>
            SenebLawApp(repository: scoped, onLock: access.lock),
      ),
    );
  } catch (_) {
    await db.close();
    await _instanceLease?.close();
    _instanceLease = null;
    runApp(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar')],
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تعذر فتح البيانات بأمان. لم يبدأ تشغيل البرنامج. '
                    'راجع مساحة التخزين والمستندات الأصلية والنسخة الاحتياطية قبل المحاولة.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: main,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SenebLawApp extends StatefulWidget {
  final AppRepository repository;
  final VoidCallback? onLock;

  const SenebLawApp({super.key, required this.repository, this.onLock});

  @override
  State<SenebLawApp> createState() => _SenebLawAppState();
}

class _SenebLawAppState extends State<SenebLawApp> {
  late final ScopedAppRepository? _workspace =
      widget.repository is ScopedAppRepository
      ? widget.repository as ScopedAppRepository
      : null;
  late final _router = createAppRouter(
    workspace: _workspace,
    onLock: widget.onLock,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return RepositoryProvider.value(
      value: repository,

      child: MultiBlocProvider(
        providers: [
          // إدارة الموكلين
          BlocProvider(create: (context) => ClientsCubit(repository)),

          // إدارة القضايا
          BlocProvider(create: (context) => CasesCubit(repository)),

          // إدارة الجلسات
          BlocProvider(create: (context) => SessionsCubit(repository)),

          // إدارة الخزينة
          BlocProvider(create: (context) => TreasuryCubit(repository)),
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

          routerConfig: _router,
          builder: _workspace == null
              ? null
              : (context, child) => CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyK,
                      control: true,
                    ): () {
                      if (_router.routeInformationProvider.value.uri.path !=
                          '/search') {
                        _router.push('/search');
                      }
                    },
                  },
                  child: Focus(autofocus: true, child: child!),
                ),

          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
