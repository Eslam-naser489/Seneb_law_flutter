import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import '../cubit/cases_cubit.dart';

class AddCaseScreen extends StatefulWidget {
  const AddCaseScreen({super.key, this.clientId});
  final String? clientId;

  @override
  State<AddCaseScreen> createState() => _AddCaseScreenState();
}

class _AddCaseScreenState extends State<AddCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _caseNumberController = TextEditingController();
  final _opponentNameController = TextEditingController();

  String? _selectedClientId;
  List<ClientEntity> _clients = [];
  bool _isLoading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final clients = await context.read<AppRepository>().getActiveClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        if (clients.any((client) => client.id == widget.clientId)) {
          _selectedClientId = widget.clientId;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'تعذر تحميل الموكلين.';
      });
    }
  }

  @override
  void dispose() {
    _caseNumberController.dispose();
    _opponentNameController.dispose();
    super.dispose();
  }

  Future<void> _saveCase() async {
    if (_saving ||
        !_formKey.currentState!.validate() ||
        _selectedClientId == null) {
      return;
    }
    setState(() => _saving = true);
    final saved = await context.read<CasesCubit>().addCase(
      clientId: _selectedClientId!,
      caseNumber: _caseNumberController.text.trim(),
      opponentName: _opponentNameController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر الحفظ. احتُفظ بالبيانات المدخلة، حاول مرة أخرى.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة قضية جديدة')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              TextButton(
                onPressed: _loadClients,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_clients.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة قضية جديدة')),
        body: const Center(
          child: Text('يجب إضافة موكل واحد على الأقل قبل تسجيل القضايا.'),
        ),
      );
    }

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('إضافة قضية جديدة')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: AppCard(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppSectionHeader(title: 'بيانات القضية الجديدة'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedClientId,
                        decoration: const InputDecoration(
                          labelText: 'اختر الموكل',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        items: _clients.map((client) {
                          return DropdownMenuItem(
                            value: client.id,
                            child: Text(client.name),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => _selectedClientId = value),
                        validator: (value) =>
                            value == null ? 'برجاء اختيار الموكل' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _caseNumberController,
                        decoration: const InputDecoration(
                          labelText: 'رقم القضية وسنتها (مثال: 123 لسنة 2026)',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'برجاء إدخال رقم القضية';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _opponentNameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الخصم (اختياري)',
                          prefixIcon: Icon(Icons.gavel_outlined),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppButton(
                        onPressed: _saving ? null : _saveCase,
                        isLoading: _saving,
                        label: 'حفظ القضية',
                        icon: Icons.check,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
