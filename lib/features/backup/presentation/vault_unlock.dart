import 'dart:io';
import 'archive_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/storage/office_cipher.dart';

class VaultUnlock extends StatefulWidget {
  const VaultUnlock({
    super.key,
    required this.setup,
    this.restore,
    required this.unlock,
  });
  final Future<void> Function(OfficeCipher, File)? restore;
  final bool setup;
  final Future<void> Function(OfficeCipher) unlock;
  @override
  State<VaultUnlock> createState() => _VaultUnlockState();
}

class _VaultUnlockState extends State<VaultUnlock> {
  final phrase = TextEditingController(), confirm = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    phrase.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit({bool recovering = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!recovering && widget.setup && phrase.text != confirm.text) {
        throw const FormatException('العبارتان غير متطابقتين.');
      }
      final cipher = OfficeCipher(phrase.text);
      if (recovering) {
        final restored = await withPickedArchive((file) async {
          await widget.restore!(cipher, file);
          return true;
        });
        if (restored != true) return;
      }
      await widget.unlock(cipher);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'تعذر فتح المكتب. تحقق من العبارة وسلامة القاعدة والمرفقات ومساحة التخزين.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.setup ? 'تأمين بيانات المكتب' : 'فتح قاعدة المكتب',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              widget.setup
                  ? 'اختر عبارة استعادة مستقلة عن أرقام الفريق واحفظها خارج الجهاز. ستحتاج إليها لفتح المكتب واستعادة نسخه على جهاز جديد.'
                  : 'أدخل عبارة استعادة المكتب، ثم افتح حسابك برقمك الفردي.',
            ),
            TextField(
              controller: phrase,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'عبارة الاستعادة'),
            ),
            if (widget.setup)
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد عبارة الاستعادة',
                ),
              ),
            if (widget.restore != null)
              OutlinedButton(
                onPressed: busy ? null : () => submit(recovering: true),
                child: const Text('استعادة مكتب من نسخة مشفرة'),
              ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'جارٍ الفتح…' : 'متابعة'),
            ),
          ],
        ),
      ),
    ),
  );
}
