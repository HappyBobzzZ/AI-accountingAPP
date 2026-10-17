import '../models/bill.dart';

/// 账单 CSV 生成（纯函数，便于单测；不依赖任何平台插件）
///
/// 输出带 UTF-8 BOM，Excel / WPS 双击打开不会乱码。
class BillCsv {
  /// 表头（顺序即列顺序）
  static const List<String> headers = [
    '日期',
    '类型',
    '分类',
    '子分类',
    '金额',
    '备注',
    '创建时间',
  ];

  /// 生成 CSV 文本（含 BOM 与表头）
  static String build(List<Bill> bills) {
    final sb = StringBuffer('\uFEFF');
    sb.writeln(headers.join(','));
    for (final b in bills) {
      sb.writeln([
        b.date,
        b.type,
        b.category,
        b.subcategory,
        b.amount.toStringAsFixed(2),
        b.remark,
        b.createdAt,
      ].map(_escape).join(','));
    }
    return sb.toString();
  }

  /// 文件名：AI记账_账单备份_20261017_1855.csv
  static String fileName([DateTime? now]) {
    final n = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'AI记账_账单备份_${n.year}${two(n.month)}${two(n.day)}'
        '_${two(n.hour)}${two(n.minute)}.csv';
  }

  /// 含逗号/引号/换行的字段需要用双引号包裹，内部引号翻倍
  static String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
