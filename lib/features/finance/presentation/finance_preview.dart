import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

class FinancePreview extends StatelessWidget {
  const FinancePreview({
    super.key,
    required this.bytes,
    required this.name,
    required this.authorize,
  });
  final Uint8List bytes;
  final String name;
  final Future<void> Function() authorize;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('معاينة المستند المالي')),
    body: PdfPreview(
      build: (_) async {
        await authorize();
        return bytes;
      },
      allowSharing: false,
      allowPrinting: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      actions: [
        IconButton(
          tooltip: 'حفظ PDF',
          icon: const Icon(Icons.save_alt),
          onPressed: () async {
            try {
              await authorize();
              await FilePicker.saveFile(
                dialogTitle: 'حفظ مستند مالي',
                fileName: name,
                mimeType: 'application/pdf',
                bytes: bytes,
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تعذر الحفظ. تحقق من الجلسة ومكان الملف.'),
                  ),
                );
              }
            }
          },
        ),
        IconButton(
          tooltip: 'طباعة',
          icon: const Icon(Icons.print),
          onPressed: () async {
            try {
              await authorize();
              await Printing.layoutPdf(
                name: name,
                onLayout: (_) async {
                  await authorize();
                  return bytes;
                },
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('تعذرت الطباعة.')));
              }
            }
          },
        ),
      ],
    ),
  );
}
