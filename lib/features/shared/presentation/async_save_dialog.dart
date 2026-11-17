import 'package:flutter/material.dart';

/// ننتظر إزالة النافذة من الشاشة قبل التخلص من متحكمات الحقول.
Future<bool?> showAsyncSaveDialog({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    builder: builder,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

/// يمنع إغلاق نافذة الحفظ قبل اكتمال العملية.
class AsyncSaveDialog extends StatefulWidget {
  final String title;
  final Widget content;
  final String saveLabel;
  final String? Function() validate;
  final Future<bool> Function() onSave;
  final String? Function(Object)? errorMessage;

  const AsyncSaveDialog({
    super.key,
    required this.title,
    required this.content,
    required this.validate,
    required this.onSave,
    this.errorMessage,
    this.saveLabel = 'حفظ',
  });

  @override
  State<AsyncSaveDialog> createState() => _AsyncSaveDialogState();
}

class _AsyncSaveDialogState extends State<AsyncSaveDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final validationError = widget.validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var saved = false;
    String? message;
    try {
      saved = await widget.onSave();
    } catch (error) {
      message = widget.errorMessage?.call(error);
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error =
            message ?? 'تعذر الحفظ. احتُفظ بالبيانات المدخلة، حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Color(0xFF0A1F44),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AbsorbPointer(absorbing: _saving, child: widget.content),
            if (_error != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(widget.saveLabel),
        ),
      ],
    ),
  );
}
