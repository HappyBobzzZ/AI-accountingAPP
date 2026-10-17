import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../theme/app_theme.dart';
import 'bill_form.dart';

/// 账单确认/编辑弹窗 —— 首页"AI 识别后确认"与账单列表"编辑"共用
///
/// 表单本身在 [BillForm] 里，这里只负责弹窗外壳（拖拽条、标题、
/// 识别原文回显、滚动与键盘避让）。
Future<void> showBillEditSheet({
  required BuildContext context,
  required Bill bill,
  required Future<void> Function(Bill) onSave,
  String title = '确认记账',
  String saveLabel = '确认保存',
  String? sourceText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BillSheet(
      bill: bill,
      onSave: onSave,
      title: title,
      saveLabel: saveLabel,
      sourceText: sourceText,
    ),
  );
}

class _BillSheet extends StatelessWidget {
  final Bill bill;
  final Future<void> Function(Bill) onSave;
  final String title;
  final String saveLabel;
  final String? sourceText;

  const _BillSheet({
    required this.bill,
    required this.onSave,
    required this.title,
    required this.saveLabel,
    this.sourceText,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppGap.xl, AppGap.sm, AppGap.xl, AppGap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppGap.lg),

            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: palette.textSecondary),
                  style: IconButton.styleFrom(
                    backgroundColor: palette.surfaceAlt,
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),

            // 识别原文回显：让用户知道"我听到的是这句话"，
            // 听错了可以直接关掉重说，而不是对着表单猜哪里错了
            if (sourceText != null && sourceText!.isNotEmpty) ...[
              const SizedBox(height: AppGap.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppGap.md, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sourceText!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppGap.xl),

            BillForm(
              original: bill,
              submitLabel: saveLabel,
              onSubmit: (edited) async {
                await onSave(edited);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
