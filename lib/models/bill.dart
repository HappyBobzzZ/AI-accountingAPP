/// 账单数据模型
class Bill {
  final int? id;
  final String type;       // "支出" 或 "收入"
  final String category;   // 餐饮/交通/购物/娱乐/居住/人情/医疗/薪资/其他
  final String subcategory; // 子分类，如 三餐/水果/打车；空串表示未分类
  final double amount;
  final String date;       // YYYY-MM-DD
  final String remark;
  final String createdAt;  // ISO8601

  const Bill({
    this.id,
    required this.type,
    required this.category,
    this.subcategory = '',
    required this.amount,
    required this.date,
    required this.remark,
    required this.createdAt,
  });

  /// 从 JSON 创建（API 返回或数据库读取）
  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'] as int?,
      type: json['type'] as String? ?? '支出',
      category: json['category'] as String? ?? '其他',
      subcategory: json['subcategory'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: json['date'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  /// 转换为 JSON（用于数据库存储）
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'category': category,
      'subcategory': subcategory,
      'amount': amount,
      'date': date,
      'remark': remark,
      'created_at': createdAt,
    };
  }

  /// 从 API 响应创建（不含 id 和 created_at，由数据库补充）
  factory Bill.fromApiResponse(Map<String, dynamic> json) {
    return Bill(
      type: json['type'] as String? ?? '支出',
      category: json['category'] as String? ?? '其他',
      subcategory: json['subcategory'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: json['date'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  /// 创建一个用于编辑的副本
  Bill copyWith({
    int? id,
    String? type,
    String? category,
    String? subcategory,
    double? amount,
    String? date,
    String? remark,
    String? createdAt,
  }) {
    return Bill(
      id: id ?? this.id,
      type: type ?? this.type,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      remark: remark ?? this.remark,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 是否为支出
  bool get isExpense => type == '支出';

  /// 内容指纹 — 用于导入去重（同一笔账单的各字段组合）
  /// 注意：不含 id / createdAt，这两项在不同设备上必然不同
  String get fingerprint =>
      '$date|$type|$category|$subcategory|${amount.toStringAsFixed(2)}|$remark';

  @override
  String toString() =>
      'Bill(id:$id, $type, $category, ¥$amount, $date, $remark)';
}

/// 账单分类
///
/// 只保留数据（名称 + 显示名）。图标与配色属于展示层，
/// 放在 `lib/theme/category_style.dart`，避免模型依赖 Flutter。
class BillCategory {
  final String name;
  final String label; // 中文显示名

  const BillCategory(this.name, this.label);

  static const List<BillCategory> expenseCategories = [
    BillCategory('餐饮', '餐饮'),
    BillCategory('交通', '交通'),
    BillCategory('购物', '购物'),
    BillCategory('娱乐', '娱乐'),
    BillCategory('居住', '居住'),
    BillCategory('人情', '人情'),
    BillCategory('医疗', '医疗'),
    BillCategory('其他', '其他'),
  ];

  static const List<BillCategory> incomeCategories = [
    BillCategory('薪资', '薪资'),
    BillCategory('其他', '其他'),
  ];

  /// 获取所有分类（支出 + 收入）
  static List<BillCategory> get allCategories {
    final all = [...expenseCategories];
    for (final c in incomeCategories) {
      if (!all.any((e) => e.name == c.name)) {
        all.add(c);
      }
    }
    return all;
  }

  /// 获取所有分类名称列表
  static List<String> get categoryNames =>
      allCategories.map((c) => c.name).toList();

  /// 获取某类型下的分类列表
  static List<BillCategory> forType(String type) =>
      type == '收入' ? incomeCategories : expenseCategories;

  /// 各分类的子分类（手动页/确认弹窗 chips 来源，与解析词表保持一致）
  static const Map<String, List<String>> subcategories = {
    '餐饮': ['三餐', '水果', '零食', '饮料', '酒水', '买菜'],
    '交通': ['打车', '公交', '地铁', '火车高铁', '加油', '停车'],
    '购物': ['服装', '数码', '洗护用品', '美妆护肤', '日用', '理发'],
    '娱乐': ['电影', '聚会', '会员', '游戏', '旅游'],
    '居住': ['房租', '水电燃气', '宽带通信', '物业'],
    '人情': ['红包', '礼物', '孝敬长辈', '生日'],
    '医疗': ['药品', '门诊', '体检'],
    '薪资': ['工资', '奖金', '福利', '兼职'],
  };

  /// 获取某分类的子分类列表
  static List<String> subcategoriesFor(String category) =>
      subcategories[category] ?? const [];
}
