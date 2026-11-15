import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../../core/database/database.dart';
import '../domain/finance_models.dart';

/// لا تغادر أي أسماء أو مبالغ الجلسة المفتوحة. التنبيه العام يطلب مراجعة الأقساط.
class InstallmentReminders {
  InstallmentReminders(this.db);
  final AppDatabase db;
  static final status = ValueNotifier<String>(
    'التذكير داخل صفحة الأقساط متاح. فعّل إشعارات الجهاز من الخزينة.',
  );
  final plugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<dynamic>? _subscription;
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _ready = false;
  String? _shownDay;
  String? _scheduledSignature;
  static const _settings = InitializationSettings(
    android: AndroidInitializationSettings('ic_notification'),
    windows: WindowsInitializationSettings(
      appName: 'سِنِب',
      appUserModelId: 'SenebLaw.Office',
      guid: 'ace13889-9716-4e4f-81eb-90bb21685db1',
    ),
  );
  void start() {
    tzdata.initializeTimeZones();
    _subscription = db
        .customSelect(
          "SELECT value_json FROM app_settings WHERE key = 'installment_notifications' AND deleted_at IS NULL",
          readsFrom: {
            db.appSettings,
            db.installments,
            db.paymentAllocations,
            db.clientLedgerEntries,
          },
        )
        .watch()
        .listen(
          (_) {
            _refresh();
          },
          onError: (_) {
            status.value = 'تعذر تحديث التذكيرات. راجع الأقساط داخل البرنامج.';
          },
        );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  void _refresh() {
    _pending = _pending.then((_) => _sync()).catchError((_) {
      status.value =
          'تعذر تشغيل إشعارات الجهاز. التذكير داخل صفحة الأقساط متاح.';
    });
  }

  Future<void> _sync() async {
    final settings = await db
        .customSelect(
          "SELECT value_json FROM app_settings WHERE key = 'installment_notifications' AND deleted_at IS NULL",
        )
        .getSingleOrNull();
    if (settings?.read<String>('value_json') != 'true') {
      if (settings != null && !_ready) {
        _ready = await plugin.initialize(settings: _settings) ?? false;
      }
      if (_ready && _scheduledSignature != 'disabled') await plugin.cancelAll();
      _scheduledSignature = 'disabled';
      status.value = 'إشعارات الجهاز متوقفة. التذكير داخل صفحة الأقساط متاح.';
      return;
    }
    if (!_ready) {
      _ready = await plugin.initialize(settings: _settings) ?? false;
    }
    if (!_ready) throw StateError('Notifications unavailable');
    final installments = await (db.select(
      db.installments,
    )..where((t) => t.voidedAt.isNull())).get();
    final allocations = await (db.select(
      db.paymentAllocations,
    )..where((t) => t.voidedAt.isNull())).get();
    final cairo = tz.getLocation('Africa/Cairo');
    final now = tz.TZDateTime.now(cairo);
    final dates = reminderDates(installments, allocations);
    final scheduled = dates
        .map((d) => tz.TZDateTime(cairo, d.year, d.month, d.day, 9))
        .where((d) => d.isAfter(now))
        .toList();
    final hasDue = dates.any(
      (d) => !tz.TZDateTime(cairo, d.year, d.month, d.day, 9).isAfter(now),
    );
    // إلغاء التذكيرات المجدولة مدعوم أيضًا في Windows دون هوية حزمة.
    final signature = scheduled.map((d) => d.toIso8601String()).join('|');
    if (signature != _scheduledSignature) {
      await plugin.cancelAll();
      for (final date in scheduled) {
        await plugin.zonedSchedule(
          id: date.year * 10000 + date.month * 100 + date.day,
          title: 'تذكير المكتب',
          body: 'افتح البرنامج وراجع الأقساط المستحقة.',
          scheduledDate: date,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      _scheduledSignature = signature;
    }
    final day = '${now.year}-${now.month}-${now.day}';
    if (hasDue && _shownDay != day) {
      await plugin.show(
        id: 1,
        title: 'تذكير المكتب',
        body: 'افتح صفحة الأقساط لمراجعة المواعيد والسداد.',
        notificationDetails: _details,
      );
      _shownDay = day;
    }
    status.value =
        'إشعارات محلية مفعلة؛ الساعة ٩ صباحًا بتوقيت القاهرة. التسليم يخضع لإعدادات النظام.';
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'installments',
      'تذكير الأقساط',
      channelDescription: 'تنبيه عام دون أسماء أو مبالغ',
      visibility: NotificationVisibility.private,
    ),
    windows: WindowsNotificationDetails(),
  );
  static Future<bool> requestPermission() async {
    final p = FlutterLocalNotificationsPlugin();
    await p.initialize(settings: _settings);
    return await p
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        true;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _timer?.cancel();
    await _pending;
  }
}

List<DateTime> reminderDates(
  List<Installment> installments,
  List<PaymentAllocation> allocations,
) {
  final dates = <DateTime>{};
  for (final i in installments.where((i) => i.voidedAt == null)) {
    final paid = checkedSum(
      allocations
          .where((a) => a.voidedAt == null && a.installmentId == i.id)
          .map((a) => a.amountMinor),
    );
    if (paid < i.amountMinor) {
      dates.add(
        DateTime(i.dueAt.year, i.dueAt.month, i.dueAt.day - i.reminderDays),
      );
    }
  }
  return dates.toList()..sort();
}
