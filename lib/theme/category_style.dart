import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 分类的展示样式（图标 + 底色）
///
/// 之前用 emoji 当图标，不同 ROM 上字形、大小、基线全不一样，
/// 是"看起来不上档次"最直接的来源。这里统一换成 Material 线性图标，
/// 每类配一个低饱和底色，靠颜色帮助扫读而不是靠花哨。
@immutable
class CategoryStyle {
  final IconData icon;
  final Color tint;
  final Color tintDark;

  const CategoryStyle(this.icon, this.tint, this.tintDark);

  static const _fallback =
      CategoryStyle(Icons.push_pin_rounded, Color(0xFFF0F2F6), Color(0xFF262B35));

  static const Map<String, CategoryStyle> _map = {
    '餐饮': CategoryStyle(
        Icons.ramen_dining_rounded, Color(0xFFFFF1E8), Color(0xFF3A2A1E)),
    '交通': CategoryStyle(
        Icons.directions_car_rounded, Color(0xFFEAF1FF), Color(0xFF1E2A42)),
    '购物': CategoryStyle(
        Icons.shopping_bag_rounded, Color(0xFFFDECF3), Color(0xFF3A2029)),
    '娱乐': CategoryStyle(
        Icons.sports_esports_rounded, Color(0xFFF3EDFE), Color(0xFF2C2340)),
    '居住': CategoryStyle(
        Icons.home_rounded, Color(0xFFE5F7F4), Color(0xFF17332F)),
    '人情': CategoryStyle(
        Icons.card_giftcard_rounded, Color(0xFFFDEDEA), Color(0xFF3A2521)),
    '医疗': CategoryStyle(
        Icons.medical_services_rounded, Color(0xFFFDECEC), Color(0xFF3A1F1F)),
    '薪资': CategoryStyle(
        Icons.account_balance_wallet_rounded, Color(0xFFE8F7EE), Color(0xFF173024)),
    '其他': _fallback,
  };

  static CategoryStyle of(String category) => _map[category] ?? _fallback;

  /// 图标本身的颜色：同色系压深一档，保证在浅底上够清晰
  static Color iconColor(BuildContext context, String category) {
    final style = of(category);
    if (context.isDark) {
      return Color.lerp(style.tint, Colors.white, 0.55)!;
    }
    return Color.lerp(style.tint, Colors.black, 0.62)!;
  }

  static Color background(BuildContext context, String category) =>
      context.isDark ? of(category).tintDark : of(category).tint;
}

/// 分类图标容器：圆角方块 + 淡色底 + 线性图标
class CategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  const CategoryIcon({
    super.key,
    required this.category,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CategoryStyle.background(context, category),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        CategoryStyle.of(category).icon,
        size: size * 0.5,
        color: CategoryStyle.iconColor(context, category),
      ),
    );
  }
}

/// 分类网格选择器（手动记账 / 确认弹窗共用）
class CategoryPicker extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const columns = 4;
      const gap = AppGap.sm;
      final itemWidth =
          (constraints.maxWidth - gap * (columns - 1)) / columns;

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: categories.map((name) {
          final isSelected = name == selected;
          return SizedBox(
            width: itemWidth,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onSelected(name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.palette.brandSoft
                      : context.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CategoryStyle.of(name).icon,
                      size: 21,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : CategoryStyle.iconColor(context, name),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }
}
