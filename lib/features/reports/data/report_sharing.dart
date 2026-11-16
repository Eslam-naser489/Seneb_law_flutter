import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/database/app_repository.dart';
import '../domain/report_models.dart';

class HandoffResult {
  const HandoffResult(this.status, {this.target, this.errorCode});
  final String status;
  final String? target, errorCode;
}

abstract class ShareGateway {
  Future<HandoffResult> handoff(
    ReportBundle bundle,
    String channel,
    String format,
    String recipient,
    Future<void> Function() authorize,
  );
}

class NativeShareGateway implements ShareGateway {
  Future<HandoffResult> handoffWord(
    Uint8List bytes,
    String channel,
    Future<void> Function() authorize,
  ) async {
    const mime =
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    await authorize();
    if (channel == 'SAVE') {
      final path = await FilePicker.saveFile(
        dialogTitle: 'حفظ مستند Word',
        fileName: 'document.docx',
        mimeType: mime,
        bytes: bytes,
      );
      return HandoffResult(path == null ? 'CANCELLED' : 'SAVED');
    }
    final root = Directory(
      p.join((await getTemporaryDirectory()).path, 'seneb-report-shares'),
    );
    await root.create(recursive: true);
    await _cleanOldFiles(root);
    final directory = Directory(p.join(root.path, const Uuid().v4()));
    await directory.create();
    final file = await File(
      p.join(directory.path, 'document.docx'),
    ).writeAsBytes(bytes, flush: true);
    await authorize();
    if (channel == 'OPEN') {
      final result = await OpenFilex.open(file.path, type: mime);
      return HandoffResult(
        result.type == ResultType.done ? 'OPENED' : 'FAILED',
      );
    }
    if (channel != 'NATIVE') throw ArgumentError('قناة غير مدعومة.');
    final result = await SharePlus.instance.share(
      ShareParams(
        title: 'مشاركة مستند بعد المراجعة',
        files: [XFile(file.path, mimeType: mime)],
      ),
    );
    return HandoffResult(switch (result.status) {
      ShareResultStatus.success => 'OPENED',
      ShareResultStatus.dismissed => 'CANCELLED',
      ShareResultStatus.unavailable => 'UNAVAILABLE',
    });
  }

  @override
  Future<HandoffResult> handoff(
    ReportBundle bundle,
    String channel,
    String format,
    String recipient,
    Future<void> Function() authorize,
  ) async {
    final report = bundle.report;
    if (channel == 'COPY') {
      await authorize();
      await Clipboard.setData(ClipboardData(text: report.textContent));
      return const HandoffResult('COPIED');
    }
    if (channel.startsWith('WHATSAPP')) {
      final uri = whatsappDraftUri(
        recipient,
        report.textContent,
        web: channel == 'WHATSAPP_WEB',
      );
      if (uri.toString().length > 12000) {
        throw const FormatException(
          'النص طويل للرابط؛ استخدم نسخ النص والإرفاق اليدوي.',
        );
      }
      await authorize();
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return HandoffResult(
        opened ? 'OPENED' : 'FAILED',
        errorCode: opened ? null : 'LAUNCH_FAILED',
      );
    }
    if (channel == 'PRINT') {
      await authorize();
      final printed = await Printing.layoutPdf(
        name: 'report.pdf',
        onLayout: (_) async {
          await authorize();
          return bundle.pdf;
        },
      );
      return HandoffResult(printed ? 'OPENED' : 'CANCELLED');
    }
    final files = <(String, Uint8List)>[
      if (format == 'PDF') ('report.pdf', bundle.pdf),
      if (format == 'PNG')
        for (var i = 0; i < bundle.images.length; i++)
          ('report-page-${i + 1}.png', bundle.images[i]),
    ];
    if (channel == 'SAVE') {
      var saved = 0;
      for (final file in files) {
        await authorize();
        final path = await FilePicker.saveFile(
          dialogTitle: files.length > 1
              ? 'حفظ صفحة ${saved + 1} من ${files.length}'
              : 'حفظ الملف',
          fileName: file.$1,
          mimeType: format == 'PDF' ? 'application/pdf' : 'image/png',
          bytes: file.$2,
        );
        if (path == null) {
          return HandoffResult(
            saved == 0 ? 'CANCELLED' : 'FAILED',
            errorCode: saved == 0 ? null : 'PARTIAL_EXPORT_$saved',
          );
        }
        saved++;
      }
      return const HandoffResult('SAVED');
    }
    final outgoing = <XFile>[];
    if (files.isNotEmpty) {
      final root = Directory(
        p.join((await getTemporaryDirectory()).path, 'seneb-report-shares'),
      );
      await root.create(recursive: true);
      await _cleanOldFiles(root);
      final directory = Directory(p.join(root.path, const Uuid().v4()));
      await directory.create();
      for (final file in files) {
        final saved = await File(
          p.join(directory.path, file.$1),
        ).writeAsBytes(file.$2, flush: true);
        outgoing.add(
          XFile(
            saved.path,
            mimeType: format == 'PDF' ? 'application/pdf' : 'image/png',
          ),
        );
      }
    }
    await authorize();
    final result = await SharePlus.instance.share(
      ShareParams(
        title: 'مشاركة مستند بعد المراجعة',
        subject: 'تقرير المكتب',
        text: format == 'TEXT' ? report.textContent : null,
        files: outgoing.isEmpty ? null : outgoing,
      ),
    );
    return HandoffResult(
      switch (result.status) {
        ShareResultStatus.success => 'OPENED',
        ShareResultStatus.dismissed => 'CANCELLED',
        ShareResultStatus.unavailable => 'UNAVAILABLE',
      },
      target: result.raw.isEmpty
          ? null
          : result.raw.substring(
              0,
              result.raw.length > 200 ? 200 : result.raw.length,
            ),
    );
  }

  Future<void> _cleanOldFiles(Directory root) async {
    final canonical = await root.resolveSymbolicLinks();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(p.basename(entity.path))) {
        continue;
      }
      final resolved = await entity.resolveSymbolicLinks();
      if (p.isWithin(canonical, resolved) &&
          (await entity.stat()).modified.isBefore(
            DateTime.now().subtract(const Duration(hours: 24)),
          )) {
        await Directory(resolved).delete(recursive: true);
      }
    }
  }
}

class ReportSharing {
  ReportSharing(this.repo, {ShareGateway? gateway})
    : gateway = gateway ?? NativeShareGateway();
  final ScopedAppRepository repo;
  final ShareGateway gateway;
  Future<HandoffResult> share(
    ReportBundle preview, {
    required String recipient,
    required String channel,
    required String format,
    required bool reviewed,
  }) async {
    final id = await repo.beginShare(
      preview.report.id,
      expectedHash: preview.report.contentHash,
      recipient: recipient,
      channel: channel,
      format: format,
      reviewed: reviewed,
    );
    try {
      final bundle = await repo.readReport(preview.report.id);
      final result = await gateway.handoff(
        bundle,
        channel,
        format,
        recipient,
        () => repo.recheckShare(id),
      );
      await repo.finishShare(
        id,
        result.status,
        target: result.target,
        errorCode: result.errorCode,
      );
      return result;
    } catch (error) {
      // قد تُقفل الجلسة عند العودة؛ تبقى المحاولة غير مؤكدة بدل ادعاء نجاحها.
      try {
        await repo.finishShare(id, 'FAILED', errorCode: 'HANDOFF_FAILED');
      } catch (_) {}
      rethrow;
    }
  }
}
