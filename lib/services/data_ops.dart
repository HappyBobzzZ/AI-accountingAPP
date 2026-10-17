import 'package:flutter/material.dart';

import '../widgets/app_widgets.dart';
import 'app_events.dart';
import 'api_service.dart';
import 'bill_import.dart';
import 'database_service.dart';
import 'error_reporter.dart';
import 'export_service.dart';

/// 数据操作（导入 / 导出）—— 设置页与账单页共用同一份流程，
/// 避免两处各写一遍确认弹窗和错误处理。
bool _importing = false;

/// 导出全部账单为 CSV，再交给系统分享面板
Future<void> exportBillsFlow(BuildContext context) async {
  final bills = await DatabaseService.instance.getAllBills();
  if (!context.mounted) return;

  if (bills.isEmpty) {
    showAppSnack(context, '还没有账单可以导出');
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导出账单备份'),
      content: Text(
        '将把全部 ${bills.length} 条账单导出为 CSV 文件，可用 Excel / WPS 打开。\n\n'
        '点「导出」后会弹出系统分享面板，可存到文件管理器、发到微信或邮箱。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 42)),
          child: const Text('导出'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  try {
    // iPad/Mac 需要锚点，安卓忽略
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await ExportService.shareCsv(bills, sharePositionOrigin: origin);
  } catch (e, st) {
    ErrorReporter.report('export_csv', e, st);
    if (context.mounted) {
      showAppSnack(context, '导出失败：$e', kind: SnackKind.error);
    }
  }
}

/// 从电脑后端增量导入历史账单（需手机与电脑在同一 WiFi）
Future<void> importBillsFlow(BuildContext context) async {
  if (_importing) return;
  _importing = true;
  showAppSnack(context, '正在从电脑读取账单…');

  try {
    final bills = await ApiService.fetchImportBills();
    if (!context.mounted) return;

    if (bills == null || bills.isEmpty) {
      showAppSnack(context, '没读到账单：请确认手机和电脑连的是同一个 WiFi');
      return;
    }

    // 增量导入：按内容指纹逐条去重，库里已有的跳过、只插新的
    final existing = await DatabaseService.instance.getExistingFingerprints();
    if (!context.mounted) return;

    final plan = planImport(bills, existing);

    if (plan.isEmpty) {
      showAppSnack(context, '这 ${bills.length} 条账单都已经在手机里了');
      return;
    }

    final count = await DatabaseService.instance.bulkInsertBills(plan.fresh);
    AppEvents.instance.billsChanged();
    if (!context.mounted) return;

    showAppSnack(
      context,
      plan.duplicated > 0
          ? '已导入 $count 条，跳过 ${plan.duplicated} 条重复'
          : '已导入 $count 条历史账单',
      kind: SnackKind.success,
    );
  } catch (e, st) {
    ErrorReporter.report('import', e, st);
    if (!context.mounted) return;
    showAppSnack(context, '导入失败，错误已上报电脑', kind: SnackKind.error);

    // 弹出完整错误详情，方便截图
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('导入失败'),
        content: SingleChildScrollView(child: SelectableText(e.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } finally {
    _importing = false;
  }
}
