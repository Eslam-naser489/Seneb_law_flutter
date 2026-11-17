import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/app/theme/app_colors.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import '../cubit/sessions_cubit.dart';

class AddSessionScreen extends StatefulWidget {
  const AddSessionScreen({super.key});

  @override
  State<AddSessionScreen> createState() => _AddSessionScreenState();
}

class _AddSessionScreenState extends State<AddSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _courtController = TextEditingController();
  final _circleController = TextEditingController();
  final _decisionController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  String? _selectedCaseId;
  List<CaseWithClient> _cases = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cases = await context.read<AppRepository>().getCasesWithClients();
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذر تحميل القضايا.';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (mounted && picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  void dispose() {
    _courtController.dispose();
    _circleController.dispose();
    _decisionController.dispose();
    super.dispose();
  }

  Future<void> _saveSession() async {
    if (_saving ||
        !_formKey.currentState!.validate() ||
        _selectedCaseId == null) {
      return;
    }
    setState(() => _saving = true);
    final saved = await context.read<SessionsCubit>().addSession(
      caseId: _selectedCaseId!,
      sessionDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      courtLocation: _courtController.text.trim(),
      circleNumber: _circleController.text.trim(),
      decision: _decisionController.text.trim(),
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة جلسة جديدة')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              TextButton(
                onPressed: _loadCases,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_cases.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة جلسة جديدة')),
        body: const Center(
          child: Text('يجب إضافة قضية واحدة على الأقل قبل تسجيل الجلسات.'),
        ),
      );
    }

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('إضافة جلسة جديدة')),
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
                      const AppSectionHeader(title: 'بيانات الجلسة والمحكمة'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCaseId,
                        decoration: const InputDecoration(
                          labelText: 'اختر القضية',
                          prefixIcon: Icon(Icons.gavel_outlined),
                        ),
                        items: _cases.map((c) {
                          return DropdownMenuItem(
                            value: c.caseEntity.id,
                            child: Text(
                              '${c.caseEntity.caseNumber} - ${c.client.name}',
                            ),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedCaseId = val),
                        validator: (val) =>
                            val == null ? 'برجاء اختيار القضية' : null,
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.secondaryText),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('تاريخ الجلسة', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryText),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.edit_calendar_outlined, size: 20, color: AppColors.accentBlue),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _courtController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المحكمة',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'برجاء إدخال اسم المحكمة'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _circleController,
                        decoration: const InputDecoration(
                          labelText: 'رقم الدائرة (اختياري)',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _decisionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'القرار أو التوجيهات (اختياري)',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppButton(
                        onPressed: _saving ? null : _saveSession,
                        isLoading: _saving,
                        label: 'حفظ الجلسة',
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
