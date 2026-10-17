import 'package:flutter_test/flutter_test.dart';
import 'package:ai_accounting/models/bill.dart';
import 'package:ai_accounting/services/bill_csv.dart';

/// CSV 导出格式测试 — 重点覆盖 Excel 兼容（BOM）与转义
void main() {
  Bill makeBill({
    String date = '2026-10-16',
    String type = '支出',
    String category = '餐饮',
    String subcategory = '三餐',
    double amount = 25,
    String remark = '黄焖鸡',
    String createdAt = '2026-10-16T12:00:00.000',
  }) {
    return Bill(
      type: type,
      category: category,
      subcategory: subcategory,
      amount: amount,
      date: date,
      remark: remark,
      createdAt: createdAt,
    );
  }

  test('开头有 UTF-8 BOM 与表头', () {
    final csv = BillCsv.build([]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    final lines = csv.replaceFirst('\uFEFF', '').trim().split('\n');
    expect(lines.length, 1);
    expect(lines.first, '日期,类型,分类,子分类,金额,备注,创建时间');
  });

  test('一行账单字段顺序与金额格式正确', () {
    final csv = BillCsv.build([makeBill()]);
    final rows = csv.replaceFirst('\uFEFF', '').trim().split('\n');
    expect(rows.length, 2);
    expect(rows[1], '2026-10-16,支出,餐饮,三餐,25.00,黄焖鸡,2026-10-16T12:00:00.000');
  });

  test('金额统一两位小数', () {
    final csv = BillCsv.build([makeBill(amount: 12.5)]);
    expect(csv, contains(',12.50,'));
  });

  test('含逗号的备注被引号包裹', () {
    final csv = BillCsv.build([makeBill(remark: '买菜,买肉')]);
    expect(csv, contains('"买菜,买肉"'));
  });

  test('含双引号的备注内部引号翻倍', () {
    final csv = BillCsv.build([makeBill(remark: '他说"好"')]);
    expect(csv, contains('"他说""好"""'));
  });

  test('含换行的备注被引号包裹', () {
    final csv = BillCsv.build([makeBill(remark: '第一行\n第二行')]);
    expect(csv, contains('"第一行\n第二行"'));
  });

  test('空字段保留为空列，不报错', () {
    final csv = BillCsv.build([makeBill(subcategory: '', remark: '')]);
    final rows = csv.replaceFirst('\uFEFF', '').trim().split('\n');
    expect(rows[1], '2026-10-16,支出,餐饮,,25.00,,2026-10-16T12:00:00.000');
  });

  test('文件名带日期时间', () {
    expect(
      BillCsv.fileName(DateTime(2026, 10, 17, 18, 55)),
      'AI记账_账单备份_20261017_1855.csv',
    );
    expect(
      BillCsv.fileName(DateTime(2026, 1, 5, 9, 3)),
      'AI记账_账单备份_20260105_0903.csv',
    );
  });
}
