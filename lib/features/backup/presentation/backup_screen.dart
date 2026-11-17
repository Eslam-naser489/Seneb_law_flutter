import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:seneb_law/app/theme/app_colors.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/storage/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<String?> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await operation();
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذرت العملية. لم تُستبدل بيانات التطبيق. '
              'راجع صلاحية المجلد وسلامة النسخة والملفات.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _export(AppRepository repository) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد حفظ النسخة',
    );
    if (path == null) return null;
    final result = await repository.createBackup(Directory(path));
    return result.isComplete
        ? 'تم إنشاء نسخة وفحص سلامتها في:\n${result.directory.path}'
        : 'النسخة غير مكتملة: ${result.missingDocumentIds.length} مستند غير متاح. '
              'لا تعتمد عليها لاستعادة جميع الملفات.\n${result.directory.path}';
  }

  Future<String?> _restore(AppRepository repository) async {
    final source = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد النسخة المحتوي على manifest.json',
    );
    if (source == null || !mounted) return null;
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد الاستعادة التجريبية',
    );
    if (destination == null || !mounted) return null;
    final backup = Directory(source);
    final output = Directory(
      p.join(destination, 'restored-${const Uuid().v4()}'),
    );
    final restored = repository is ScopedAppRepository
        ? await repository.restoreBackupIsolated(backup, output)
        : await BackupService().restoreIsolated(
            backup: backup,
            destination: output,
          );
    return 'نجح فحص النسخة واستعادتها إلى مجلد مستقل. '
        'لم تتغير قاعدة التطبيق الحالية.\n${restored.path}';
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppRepository>();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('النسخ الاحتياطي والتحقق')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(title: 'النسخ الاحتياطي والأرشيف'),
                      const Text(
                        'إصدار تجريبي: النسخ هنا غير مشفرة. احفظها في مكان خاص، وانسخ مجلد النسخة كاملًا إلى وسيط تخزين آمن.',
                        style: TextStyle(color: AppColors.secondaryText, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              onPressed: _busy ? null : () => _run(() => _export(repository)),
                              isLoading: _busy,
                              icon: Icons.backup_outlined,
                              label: 'إنشاء نسخة احتياطية',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _run(() => _restore(repository)),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('استعادة تجريبية إلى مجلد جديد'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'الاستعادة التجريبية تفحص الملفات وتنسخ البيانات فقط؛ ولا تستبدل القاعدة المفتوحة أو تفعّل الحسابات الجديدة.',
                        style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: SelectableText(
                      _message!,
                      style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.primaryText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
