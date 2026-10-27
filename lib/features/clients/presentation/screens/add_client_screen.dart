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

  @override
  void initState() {
    super.initState();
    _loadLawyers();
  }

  // جلب المحامين من الداتابيز عشان نعرضهم في الـ Dropdown
  Future<void> _loadLawyers() async {
    final repo = context.read<AppRepository>();
    var lawyers = await repo.getLawyers();
    
    // لو مفيش محامين متسجلين في المكتب، هنضيف محامي افتراضي عشان التجربة
    if (lawyers.isEmpty) {
      await repo.addLawyer('المحامي الرئيسي (أدمن)');
      lawyers = await repo.getLawyers();
    }
    
    if (mounted) {
      setState(() {
        _lawyers = lawyers;
        _selectedLawyerId = lawyers.isNotEmpty ? lawyers.first.id : null;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _saveClient() {
    // التأكد إن البيانات المطلوبة (الاسم) مكتوبة
    if (_formKey.currentState!.validate()) {
      context.read<ClientsCubit>().addClient(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        lawyerId: _selectedLawyerId,
      );
      // الرجوع للشاشة السابقة بعد الحفظ
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة موكل جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                value: _selectedLawyerId,
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
                onPressed: _saveClient,
                child: const Text('حفظ بيانات الموكل', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}