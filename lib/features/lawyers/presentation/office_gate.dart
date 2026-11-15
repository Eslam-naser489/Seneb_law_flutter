import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_repository.dart';
import '../../../core/security/pin_hasher.dart';
import '../domain/office_models.dart';

class OfficeGate extends StatefulWidget {
  const OfficeGate({
    super.key,
    required this.access,
    required this.workspace,
    this.idleTimeout = const Duration(minutes: 5),
  });
  final OfficeAccess access;
  final Widget Function(ScopedAppRepository) workspace;
  final Duration idleTimeout;

  @override
  State<OfficeGate> createState() => _OfficeGateState();
}

class _OfficeGateState extends State<OfficeGate> with WidgetsBindingObserver {
  Timer? _idle;
  DateTime _lastActivity = DateTime.now();
  StaffSession? _current;
  ScopedAppRepository? _repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    widget.access.addListener(_changeSession);
    _changeSession();
  }

  void _changeSession() {
    final session = widget.access.session;
    if (!identical(_current, session)) {
      setState(() {
        _current = session;
        _repository = session == null || session.mustChangePin
            ? null
            : widget.access.workspace(session);
      });
    }
    _activity();
  }

  void _activity() {
    _lastActivity = DateTime.now();
    _idle?.cancel();
    if (_current != null) _idle = Timer(widget.idleTimeout, widget.access.lock);
  }

  bool _key(KeyEvent event) {
    _activity();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        (state == AppLifecycleState.resumed &&
            DateTime.now().difference(_lastActivity) >= widget.idleTimeout)) {
      widget.access.lock();
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.access.removeListener(_changeSession);
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    return Listener(
      onPointerDown: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: repository != null
          ? KeyedSubtree(
              key: ObjectKey(_current),
              child: widget.workspace(repository),
            )
          : MaterialApp(
              key: ObjectKey(_current),
              debugShowCheckedModeBanner: false,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.lightTheme,
              home: _UnlockScreen(access: widget.access, temporary: _current),
            ),
    );
  }
}

class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen({required this.access, this.temporary});
  final OfficeAccess access;
  final StaffSession? temporary;

  @override
  State<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<_UnlockScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  late Future<(bool, List<UnlockProfile>)> _state = _load();
  String? _personId;
  String? _error;
  bool _busy = false;

  Future<(bool, List<UnlockProfile>)> _load() async => (
    await widget.access.needsOwnerSetup(),
    await widget.access.unlockProfiles(),
  );

  Future<void> _submit(bool setup) async {
    if (_busy || !_form.currentState!.validate()) return;
    final pin = _pin.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final temporary = widget.temporary;
      if (temporary != null) {
        await widget.access.changeTemporaryPin(temporary, pin);
      } else if (setup) {
        await widget.access.bootstrapOwner(
          _name.text,
          pin,
          legacyId: _personId,
        );
        if (mounted) {
          setState(() {
            _state = _load();
            _personId = null;
          });
        }
      } else {
        final id = _personId;
        if (id == null) throw const OfficeFailure('اختر المستخدم.');
        await widget.access.signIn(id, pin);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is OfficeFailure
              ? error.message
              : 'تعذر فتح الحساب. راجع البيانات وحاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) {
        _pin.clear();
        _confirm.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _fields(bool setup, List<UnlockProfile> profiles) {
    final temporary = widget.temporary;
    final creatingPin = setup || temporary != null;
    final choices = profiles.where((p) => setup || p.hasPin).toList();
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            setup
                ? 'إعداد مالك المكتب'
                : temporary != null
                ? 'تغيير الرقم السري المؤقت'
                : 'فتح البرنامج',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (setup)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'اختر حسابك القديم للحفاظ على إسناداته، أو أنشئ حسابًا جديدًا باسمك.',
              ),
            ),
          if (temporary == null && choices.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _personId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المستخدم'),
              hint: Text(setup ? 'حساب جديد' : 'اختر المستخدم'),
              items: [
                if (setup)
                  const DropdownMenuItem(
                    value: '',
                    child: Text('إنشاء حساب جديد'),
                  ),
                for (final profile in choices)
                  DropdownMenuItem(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (id) => setState(() => _personId = id == '' ? null : id),
            ),
          if (setup && _personId == null)
            TextFormField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'اسم مالك المكتب'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'أدخل الاسم.' : null,
            ),
          if (temporary != null) Text(temporary.person.name),
          if (!setup && temporary == null && choices.isEmpty)
            const Text(
              'لا توجد حسابات مفعّلة برقم سري. راجع إعدادات المكتب أو النسخة الاحتياطية.',
            ),
          TextFormField(
            controller: _pin,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.number,
            maxLength: 12,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: creatingPin ? 'الرقم السري الجديد' : 'الرقم السري',
            ),
            validator: (v) =>
                PinHasher.valid(v ?? '') ? null : 'أدخل من ٦ إلى ١٢ رقمًا.',
            onFieldSubmitted: creatingPin ? null : (_) => _submit(setup),
          ),
          if (creatingPin)
            TextFormField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              maxLength: 12,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'تأكيد الرقم السري'),
              validator: (v) =>
                  PinHasher.normalize(v ?? '') == PinHasher.normalize(_pin.text)
                  ? null
                  : 'الرقمان غير متطابقين.',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || (!creatingPin && choices.isEmpty)
                ? null
                : () => _submit(setup),
            child: Text(
              _busy
                  ? 'جارٍ التحقق…'
                  : creatingPin
                  ? 'حفظ الرقم السري'
                  : 'فتح البرنامج',
            ),
          ),
          if (temporary != null)
            TextButton(
              onPressed: _busy ? null : widget.access.lock,
              child: const Text('رجوع إلى اختيار المستخدم'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سِنِب للمحاماة')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: widget.temporary != null
              ? _fields(false, [])
              : FutureBuilder(
                  future: _state,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Column(
                        children: [
                          const Text('تعذر تحميل حسابات المكتب.'),
                          TextButton(
                            onPressed: () => setState(() => _state = _load()),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final (setup, profiles) = snapshot.data!;
                    return _fields(setup, profiles);
                  },
                ),
        ),
      ),
    ),
  );
}
