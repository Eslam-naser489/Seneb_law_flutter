import 'dart:async';

/// يمنع تداخل النسخ الاحتياطي مع عمليات الحفظ داخل التطبيق.
class WriteCoordinator {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}
