import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import '../cubit/cases_cubit.dart';

class AddCaseScreen extends StatefulWidget {
  const AddCaseScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    final repo = context.read<AppRepository>();
    final clients = await repo.getActiveClients();
    if (mounted) {
      setState(() {
        _clients = clients;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _caseNumberController.dispose();
    _opponentNameController.dispose();
    super.dispose();
  }

  void _saveCase() {
    if (_formKey.currentState!.validate()) {
      if (_selectedClientId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برجاء اختيار الموكل أولاً')),
        );
        return;
      }

      context.read<CasesCubit>().addCase(
        clientId: _selectedClientId!,
        caseNumber: _caseNumberController.text.trim(),
        opponentName: _opponentNameController.text.trim(),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_clients.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('إضافة قضية جديدة')),
        body: const Center(
          child: Text('يجب إضافة موكل واحد على الأقل قبل تسجيل القضايا.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة قضية جديدة')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedClientId,
                decoration: const InputDecoration(
                  labelText: 'اختر الموكل',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                items: _clients.map((client) {
                  return DropdownMenuItem(
                    value: client.id,
                    child: Text(client.name),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedClientId = value),
                validator: (value) => value == null ? 'برجاء اختيار الموكل' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _caseNumberController,
                decoration: const InputDecoration(
                  labelText: 'رقم القضية وسنتها (مثال: 123 لسنة 2026)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
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
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.gavel_outlined),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _saveCase,
                child: const Text('حفظ القضية', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}