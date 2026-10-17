import 'package:flutter_test/flutter_test.dart';
import 'package:ai_accounting/models/bill.dart';
import 'package:ai_accounting/services/bill_import.dart';

/// 导入增量去重测试 — 覆盖内容指纹与 planImport 过滤
void main() {
  Bill makeBill({
    int? id,
    String date = '2026-10-16',
    String type = '支出',
    String category = '餐饮',
    String subcategory = '三餐',
    double amount = 25,
    String remark = '黄焖鸡',
    String createdAt = '2026-10-16T12:00:00.000',
  }) {
    return Bill(
      id: id,
      type: type,
      category: category,
      subcategory: subcategory,
      amount: amount,
      date: date,
      remark: remark,
      createdAt: createdAt,
    );
  }

  group('内容指纹', () {
    test('id / createdAt 不同不影响指纹', () {
      final a = makeBill(id: 1);
      final b = makeBill(
          id: 99, createdAt: '2026-10-17T08:00:00.000');
      expect(a.fingerprint, b.fingerprint);
    });

    test('金额按两位小数归一（25 与 25.0 相同）', () {
      expect(makeBill(amount: 25).fingerprint,
          makeBill(amount: 25.0).fingerprint);
    });

    test('任一业务字段不同则指纹不同', () {
      final base = makeBill().fingerprint;
      expect(makeBill(amount: 25.5).fingerprint, isNot(base));
      expect(makeBill(date: '2026-10-15').fingerprint, isNot(base));
      expect(makeBill(remark: '火锅').fingerprint, isNot(base));
      expect(makeBill(category: '交通').fingerprint, isNot(base));
      expect(makeBill(subcategory: '').fingerprint, isNot(base));
      expect(makeBill(type: '收入').fingerprint, isNot(base));
    });
  });

  group('planImport', () {
    test('空库 → 全部导入，无跳过', () {
      final incoming = [makeBill(id: null), makeBill(remark: '火锅')];
      final plan = planImport(incoming, <String>{});
      expect(plan.fresh.length, 2);
      expect(plan.duplicated, 0);
      expect(plan.isEmpty, isFalse);
    });

    test('库里全有 → 全部跳过', () {
      final incoming = [makeBill(), makeBill(remark: '火锅')];
      final existing = incoming.map((b) => b.fingerprint).toSet();
      final plan = planImport(incoming, existing);
      expect(plan.isEmpty, isTrue);
      expect(plan.duplicated, 2);
    });

    test('部分重复 → 只插新的', () {
      final old = makeBill(remark: '黄焖鸡');
      final incoming = [
        makeBill(remark: '黄焖鸡'), // 库里已有
        makeBill(remark: '火锅'), // 新
      ];
      final plan = planImport(incoming, {old.fingerprint});
      expect(plan.fresh.length, 1);
      expect(plan.fresh.single.remark, '火锅');
      expect(plan.duplicated, 1);
    });

    test('本批内部重复 → 只插一条', () {
      final incoming = [makeBill(), makeBill(), makeBill(remark: '火锅')];
      final plan = planImport(incoming, <String>{});
      expect(plan.fresh.length, 2);
      expect(plan.duplicated, 1);
    });

    test('空输入 → 空计划', () {
      final plan = planImport([], <String>{});
      expect(plan.isEmpty, isTrue);
      expect(plan.duplicated, 0);
    });
  });
}
