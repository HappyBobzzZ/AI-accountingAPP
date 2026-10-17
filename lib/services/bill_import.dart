import '../models/bill.dart';

/// 导入计划 — 过滤后的待插入列表 + 被跳过的重复条数
class ImportPlan {
  /// 库中不存在、可以插入的账单（内部已去重）
  final List<Bill> fresh;

  /// 因重复被跳过的条数（库里已有 + 本次返回内部重复）
  final int duplicated;

  const ImportPlan(this.fresh, this.duplicated);

  bool get isEmpty => fresh.isEmpty;
}

/// 按内容指纹（日期+类型+分类+子分类+金额+备注）算出真正需要插入的账单
///
/// [existing] 为库中已有账单的指纹集合。同一批数据里自带的重复也会被去掉，
/// 因此导入可以反复执行而不会产生重复账单。
ImportPlan planImport(List<Bill> incoming, Set<String> existing) {
  final seen = <String>{};
  final fresh = <Bill>[];
  var duplicated = 0;

  for (final bill in incoming) {
    final fp = bill.fingerprint;
    // existing 命中 = 库里已有；seen.add 返回 false = 本批内已出现过
    if (existing.contains(fp) || !seen.add(fp)) {
      duplicated++;
      continue;
    }
    fresh.add(bill);
  }

  return ImportPlan(fresh, duplicated);
}
