import 'package:flutter/material.dart';

class LegacyTreasuryNotice extends StatelessWidget {
  const LegacyTreasuryNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsetsDirectional.all(12),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Text(
      'السجل المالي القديم للعرض فقط. إضافة الحركات متوقفة لحين مراجعة '
      'المعاملات وتفعيل الحسابات الجديدة. الأرقام المعروضة ليست رصيد الموكل.',
    ),
  );
}
