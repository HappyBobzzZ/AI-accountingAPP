import 'package:flutter/material.dart';

import '../services/app_events.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bill_form.dart';

/// 手动记账页 —— 表单本身复用 [BillForm]，与"确认/编辑"弹窗同一套
class ManualEntryPage extends StatelessWidget {
  const ManualEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手动记账')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppGap.xl, AppGap.sm, AppGap.xl, AppGap.xxl),
          children: [
            BillForm(
              submitLabel: '保存账单',
              autofocusAmount: true,
              onSubmit: (bill) async {
                await DatabaseService.instance.insertBill(bill);
                AppEvents.instance.billsChanged();
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
    );
  }
}
