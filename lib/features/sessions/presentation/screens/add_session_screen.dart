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
  
  String? _selectedCaseId;
  List<CaseWithClient> _cases = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    final repo = context.read<AppRepository>();
    final cases = await repo.getCasesWithClients();
    if (mounted) {
      setState(() => _cases = cases);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _saveSession() {
    if (_formKey.currentState!.validate() && _selectedCaseId != null) {
      context.read<SessionsCubit>().addSession(
        caseId: _selectedCaseId!,
        sessionDate: _selectedDate,
        courtLocation: _courtController.text.trim(),
      );
      context.pop();
    } else if (_selectedCaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برجاء اختيار القضية')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cases.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة جلسة جديدة')),
        body: const Center(child: Text('يجب إضافة قضية واحدة على الأقل قبل تسجيل الجلسات.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة جلسة جديدة')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCaseId,
                decoration: const InputDecoration(labelText: 'اختر القضية', border: OutlineInputBorder()),
                items: _cases.map((c) {
                  return DropdownMenuItem(
                    value: c.caseEntity.id,
                    child: Text('${c.caseEntity.caseNumber} - ${c.client.name}'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCaseId = val),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                title: const Text('تاريخ الجلسة'),
                subtitle: Text('${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _courtController,
                decoration: const InputDecoration(labelText: 'المحكمة / الدائرة', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'برجاء إدخال اسم المحكمة' : null,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _saveSession,
                child: const Text('حفظ الجلسة', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}