import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bill.dart';
import 'bill_csv.dart';

/// 账单导出 — 生成 CSV 并交给系统分享面板（微信 / 邮件 / 文件管理器 / 网盘）
///
/// 走分享面板的好处：不需要存储权限，Android 10+ 的分区存储也不用适配。
class ExportService {
  /// 写入临时目录，返回文件
  static Future<File> writeCsvFile(List<Bill> bills, {DateTime? now}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${BillCsv.fileName(now)}');
    return file.writeAsString(BillCsv.build(bills), flush: true);
  }

  /// 生成 CSV 并唤起分享面板
  ///
  /// [sharePositionOrigin] 仅 iPad/Mac 需要（锚定弹出位置），安卓可传 null。
  static Future<ShareResult> shareCsv(
    List<Bill> bills, {
    Rect? sharePositionOrigin,
  }) async {
    final file = await writeCsvFile(bills);
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'AI 记账账单备份',
        text: '共 ${bills.length} 条账单，CSV 可用 Excel / WPS 打开',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
