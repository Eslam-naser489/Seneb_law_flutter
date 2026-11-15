import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedCaseId,
                  decoration: const InputDecoration(
                    labelText: 'اختر القضية',
                    border: OutlineInputBorder(),
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
                ListTile(
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  title: const Text('تاريخ الجلسة'),
                  subtitle: Text(
                    '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _courtController,
                  decoration: const InputDecoration(
                    labelText: 'المحكمة',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'برجاء إدخال اسم المحكمة'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _circleController,
                  decoration: const InputDecoration(
                    labelText: 'الدائرة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _decisionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'القرار (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saving ? null : _saveSession,
                  child: Text(
                    _saving ? 'جارٍ الحفظ…' : 'حفظ الجلسة',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
