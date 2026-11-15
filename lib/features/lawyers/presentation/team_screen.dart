import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_repository.dart';
import '../../../core/database/database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../shared/presentation/async_save_dialog.dart';
import '../../shared/presentation/workspace_load.dart';
import '../domain/office_models.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  ScopedAppRepository get _repo =>
      context.read<AppRepository>() as ScopedAppRepository;
  late Future<List<StaffProfile>> _data = _repo.team();
  void _refresh() => setState(() => _data = _repo.team());

  Future<void> _edit([StaffProfile? existing]) async {
    final person = existing?.person;
    final name = TextEditingController(text: person?.name);
    final phone = TextEditingController(text: person?.phone);
    final email = TextEditingController(text: person?.email);
    final bar = TextEditingController(text: person?.barRegistrationNumber);
    final pin = TextEditingController();
    final confirm = TextEditingController();
    List<int>? photo;
    var removePhoto = false;
    var role = person == null
        ? OfficeRole.lawyer
        : OfficeRole.parse(person.role);
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: person == null
              ? 'إضافة عضو لفريق المكتب'
              : 'تعديل بيانات العضو',
          errorMessage: workspaceError,
          content: SizedBox(
            width: 430,
            child: Column(
              children: [
                StatefulBuilder(
                  builder: (context, update) {
                    final current =
                        photo ?? (removePhoto ? null : existing?.photo);
                    return Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _avatar(current),
                        TextButton(
                          onPressed: () async {
                            try {
                              final selection = await FilePicker.pickFile(
                                type: FileType.custom,
                                allowedExtensions: ['png', 'jpg', 'jpeg'],
                                dialogTitle: 'اختر صورة العضو',
                              );
                              if (selection?.path == null || !context.mounted) {
                                return;
                              }
                              final file = File(selection!.path!);
                              final size = await file.length();
                              if (size > 512 * 1024) {
                                throw const OfficeFailure(
                                  'حجم الصورة يتجاوز ٥١٢ كيلوبايت.',
                                );
                              }
                              final bytes = await file
                                  .openRead(0, size)
                                  .expand((chunk) => chunk)
                                  .toList();
                              if (context.mounted) {
                                update(() {
                                  photo = bytes;
                                  removePhoto = false;
                                });
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      workspaceError(error) ??
                                          'تعذر قراءة الصورة.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('اختيار صورة'),
                        ),
                        if (current != null)
                          TextButton(
                            onPressed: () => update(() {
                              photo = null;
                              removePhoto = true;
                            }),
                            child: const Text('إزالة الصورة'),
                          ),
                      ],
                    );
                  },
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                TextField(
                  controller: phone,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                ),
                TextField(
                  controller: email,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                  ),
                ),
                TextField(
                  controller: bar,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم القيد بالنقابة',
                  ),
                ),
                DropdownButtonFormField<OfficeRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'دور المكتب'),
                  items: [
                    for (final option in OfficeRole.values.where(
                      (r) => role == OfficeRole.owner
                          ? r == role
                          : r != OfficeRole.owner,
                    ))
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: role == OfficeRole.owner
                      ? null
                      : (value) => role = value!,
                ),
                if (person == null) ...[
                  _pinField(pin, 'رقم سري مؤقت'),
                  _pinField(confirm, 'تأكيد الرقم المؤقت'),
                ],
              ],
            ),
          ),
          validate: () {
            if (name.text.trim().isEmpty) return 'أدخل الاسم.';
            if (person == null && !PinHasher.valid(pin.text)) {
              return 'أدخل رقمًا سريًا من ٦ إلى ١٢ رقمًا.';
            }
            if (person == null &&
                PinHasher.normalize(pin.text) !=
                    PinHasher.normalize(confirm.text)) {
              return 'الرقمان غير متطابقين.';
            }
            return null;
          },
          onSave: () async {
            await _repo.saveStaff(
              StaffInput(
                name: name.text,
                role: role,
                phone: phone.text,
                email: email.text,
                barNumber: bar.text,
              ),
              id: person?.id,
              initialPin: pin.text,
              photo: photo,
              removePhoto: removePhoto,
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      for (final controller in [name, phone, email, bar, pin, confirm]) {
        controller.dispose();
      }
    }
  }

  Future<void> _reset(StaffProfile profile) async {
    final ownerPin = TextEditingController();
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final reason = TextEditingController();
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: 'تعيين رقم سري مؤقت',
          errorMessage: workspaceError,
          content: SizedBox(
            width: 400,
            child: Column(
              children: [
                Text(profile.person.name),
                _pinField(ownerPin, 'الرقم السري لمالك المكتب'),
                _pinField(pin, 'الرقم المؤقت الجديد'),
                _pinField(confirm, 'تأكيد الرقم المؤقت'),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'سبب التعيين'),
                ),
              ],
            ),
          ),
          validate: () {
            if (!PinHasher.valid(ownerPin.text) || !PinHasher.valid(pin.text)) {
              return 'أدخل رقمًا من ٦ إلى ١٢ رقمًا.';
            }
            if (PinHasher.normalize(pin.text) !=
                PinHasher.normalize(confirm.text)) {
              return 'الرقمان غير متطابقين.';
            }
            if (reason.text.trim().isEmpty) return 'اكتب السبب.';
            return null;
          },
          onSave: () async {
            await _repo.resetStaffPin(
              profile.person.id,
              ownerPin.text,
              pin.text,
              reason.text,
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      for (final controller in [ownerPin, pin, confirm, reason]) {
        controller.dispose();
      }
    }
  }

  Future<void> _toggle(StaffProfile profile) async {
    final reason = TextEditingController();
    try {
      final saved = await showAsyncSaveDialog(
        context: context,
        builder: (_) => AsyncSaveDialog(
          title: profile.person.isActive ? 'إيقاف الحساب' : 'تفعيل الحساب',
          errorMessage: workspaceError,
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'السبب'),
          ),
          validate: () => reason.text.trim().isEmpty ? 'اكتب السبب.' : null,
          onSave: () async {
            await _repo.setStaffActive(
              profile.person.id,
              !profile.person.isActive,
              reason.text,
            );
            return true;
          },
        ),
      );
      if (mounted && saved == true) _refresh();
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('فريق المكتب')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _edit,
      icon: const Icon(Icons.person_add),
      label: const Text('إضافة عضو'),
    ),
    body: WorkspaceLoad(
      future: _data,
      retry: _refresh,
      buildData: (profiles) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        children: [
          if (profiles.length == 1)
            const ListTile(title: Text('لم تُضف أعضاء آخرين لفريق المكتب.')),
          for (final profile in profiles)
            Card(
              child: ListTile(
                leading: _avatar(profile.photo),
                title: Text(profile.person.name),
                subtitle: Text(
                  '${OfficeRole.parse(profile.person.role).label} · '
                  '${profile.person.isActive ? 'نشط' : 'غير نشط'} · '
                  '${!profile.hasPin
                      ? 'يلزم ضبط رقم سري'
                      : profile.mustChangePin
                      ? 'رقم مؤقت'
                      : 'رقم سري مفعّل'}',
                ),
                onTap: () => context.push(
                  '/team/${Uri.encodeComponent(profile.person.id)}/workload',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _edit(profile);
                    if (action == 'pin') _reset(profile);
                    if (action == 'active') _toggle(profile);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('تعديل البيانات'),
                    ),
                    if (profile.person.role != OfficeRole.owner.code) ...[
                      const PopupMenuItem(
                        value: 'pin',
                        child: Text('تعيين رقم سري مؤقت'),
                      ),
                      PopupMenuItem(
                        value: 'active',
                        child: Text(
                          profile.person.isActive ? 'إيقاف' : 'تفعيل',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _pinField(TextEditingController controller, String label) => TextField(
  controller: controller,
  obscureText: true,
  enableSuggestions: false,
  autocorrect: false,
  keyboardType: TextInputType.number,
  maxLength: 12,
  textDirection: TextDirection.ltr,
  decoration: InputDecoration(labelText: label),
);

Widget _avatar(List<int>? bytes) => CircleAvatar(
  child: bytes == null
      ? const Icon(Icons.person)
      : ClipOval(
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            cacheWidth: 100,
            errorBuilder: (_, _, _) => const Icon(Icons.person),
          ),
        ),
);

class WorkloadScreen extends StatefulWidget {
  const WorkloadScreen({super.key, required this.staffId});
  final String staffId;
  @override
  State<WorkloadScreen> createState() => _WorkloadScreenState();
}

class _WorkloadScreenState extends State<WorkloadScreen> {
  Future<({List<ClientEntity> clients, int activeCases, int upcomingSessions})>
  _load() => (context.read<AppRepository>() as ScopedAppRepository).workload(
    widget.staffId,
  );
  late var _data = _load();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عبء العمل')),
    body: WorkspaceLoad(
      future: _data,
      retry: () => setState(() => _data = _load()),
      buildData: (d) => ListView(
        children: [
          ListTile(
            title: const Text('القضايا النشطة'),
            trailing: Text('${d.activeCases}'),
          ),
          ListTile(
            title: const Text('الجلسات القادمة'),
            trailing: Text('${d.upcomingSessions}'),
          ),
          const Divider(),
          const ListTile(title: Text('الموكلون المسندون')),
          if (d.clients.isEmpty)
            const ListTile(title: Text('لا توجد إسنادات مباشرة لموكلين.')),
          for (final client in d.clients)
            ListTile(
              title: Text(client.name),
              subtitle: client.isArchived ? const Text('مؤرشف') : null,
              onTap: () =>
                  context.push('/client/${Uri.encodeComponent(client.id)}'),
            ),
        ],
      ),
    ),
  );
}
