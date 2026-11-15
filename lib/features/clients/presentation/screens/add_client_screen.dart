import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/core/database/database.dart';
import '../cubit/clients_cubit.dart';

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedLawyerId;
  List<OfficeLawyerEntity> _lawyers = [];
  bool _saving = false;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadLawyers();
  }

  // جلب المحامين من الداتابيز عشان نعرضهم في الـ Dropdown
  Future<void> _loadLawyers() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = context.read<AppRepository>();
      var lawyers = await repo.getLawyers();
      if (lawyers.isEmpty) {
        await repo.addLawyer('المحامي الرئيسي (أدمن)');
        lawyers = await repo.getLawyers();
      }
      if (!mounted) return;
      setState(() {
        _lawyers = lawyers;
        _selectedLawyerId = lawyers.isNotEmpty ? lawyers.first.id : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذر تحميل المحامين.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final saved = await context.read<ClientsCubit>().addClient(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      lawyerId: _selectedLawyerId,
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
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('إضافة موكل جديد')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    TextButton(
                      onPressed: _loadLawyers,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الموكل',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'برجاء إدخال اسم الموكل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف (اختياري)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedLawyerId,
                        decoration: const InputDecoration(
                          labelText: 'المحامي المسؤول',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.gavel),
                        ),
                        items: _lawyers.map((lawyer) {
                          return DropdownMenuItem(
                            value: lawyer.id,
                            child: Text(lawyer.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedLawyerId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _saving ? null : _saveClient,
                        child: Text(
                          _saving ? 'جارٍ الحفظ…' : 'حفظ بيانات الموكل',
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
