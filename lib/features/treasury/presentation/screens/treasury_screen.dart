import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/treasury_cubit.dart';
import '../cubit/treasury_state.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedType = 'INCOME';

  @override
  void initState() {
    super.initState();
    context.read<TreasuryCubit>().loadTreasuryData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _showAddTransactionDialog(BuildContext context, TreasuryCubit cubit) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('إضافة حركة مالية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'INCOME', label: Text('إيراد / أتعاب')),
                    ButtonSegment(value: 'EXPENSE', label: Text('مصروفات')),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (Set<String> newSelection) {
                    setDialogState(() => _selectedType = newSelection.first);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'البيان (مثال: أتعاب قضية 123)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المبلغ (جنيه)', border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(_amountController.text) ?? 0;
                  if (_titleController.text.isNotEmpty && amount > 0) {
                    cubit.addTransaction(
                      title: _titleController.text.trim(),
                      amount: amount,
                      type: _selectedType,
                    );
                    _titleController.clear();
                    _amountController.clear();
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 1), borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$amount ج.م', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخزينة والماليات')),
      body: BlocBuilder<TreasuryCubit, TreasuryState>(
        builder: (context, state) {
          if (state is TreasuryLoading) return const Center(child: CircularProgressIndicator());
          if (state is TreasuryError) return Center(child: Text('خطأ: ${state.message}'));
          
          if (state is TreasuryLoaded) {
            return Column(
              children: [
                // كروت الملخص المالي
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      _buildSummaryCard('إيرادات', state.summary['income']!, Colors.green, Icons.arrow_downward),
                      _buildSummaryCard('مصروفات', state.summary['expense']!, Colors.red, Icons.arrow_upward),
                      _buildSummaryCard('الصافي', state.summary['net']!, Theme.of(context).primaryColor, Icons.account_balance_wallet),
                    ],
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('سجل الحركات المالية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                // قائمة الحركات
                Expanded(
                  child: state.transactions.isEmpty
                      ? const Center(child: Text('لا توجد حركات مالية مسجلة.'))
                      : ListView.builder(
                          itemCount: state.transactions.length,
                          itemBuilder: (context, index) {
                            final t = state.transactions[index];
                            final isIncome = t.type == 'INCOME';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isIncome ? Colors.green.shade100 : Colors.red.shade100,
                                child: Icon(
                                  isIncome ? Icons.add : Icons.remove,
                                  color: isIncome ? Colors.green : Colors.red,
                                ),
                              ),
                              title: Text(t.title),
                              subtitle: Text('${t.transactionDate.year}-${t.transactionDate.month}-${t.transactionDate.day}'),
                              trailing: Text(
                                '${isIncome ? '+' : '-'}${t.amount} ج.م',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isIncome ? Colors.green : Colors.red,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransactionDialog(context, context.read<TreasuryCubit>()),
        icon: const Icon(Icons.add),
        label: const Text('حركة جديدة'),
      ),
    );
  }
}
