import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';

/// 金额格式化：千分位 + 固定小数位
///
/// 纯函数，方便单测（`formatMoney(1234.5) == '1,234.50'`）。
String formatMoney(num value, {int decimals = 2, bool grouped = true}) {
  final negative = value < 0;
  final text = value.abs().toStringAsFixed(decimals);
  if (!grouped) return negative ? '-$text' : text;

  final dot = text.indexOf('.');
  final intPart = dot < 0 ? text : text.substring(0, dot);
  final decPart = dot < 0 ? '' : text.substring(dot);

  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer$decPart';
}

/// 带隐私遮罩的金额文本
///
/// 不可见时用固定长度的圆点，不按位数变化 —— 否则位数本身
/// 也会泄露"这个月花了几千还是几万"。
String moneyDisplay(
  num value, {
  required bool visible,
  int decimals = 2,
}) =>
    visible ? '¥${formatMoney(value, decimals: decimals)}' : '¥ ••••';

/// ── 卡片 ──────────────────────────────────────────────
///
/// 浅灰底 + 纯白卡，靠对比而不是阴影分层（阴影堆多了会发灰）。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppGap.lg),
    this.onTap,
    this.color,
    this.radius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// ── 小标题 ────────────────────────────────────────────
class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, AppGap.sm),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.palette.textSecondary,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: context.palette.textTertiary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ── 空状态 ────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppGap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: context.palette.textTertiary),
            ),
            const SizedBox(height: AppGap.lg),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.palette.textTertiary,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppGap.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// ── 统一提示条 ─────────────────────────────────────────
enum SnackKind { info, success, error }

void showAppSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final (IconData icon, Color color) = switch (kind) {
    SnackKind.success => (Icons.check_circle_rounded, const Color(0xFF3DD68C)),
    SnackKind.error => (Icons.error_rounded, const Color(0xFFFF7A7F)),
    SnackKind.info => (Icons.info_rounded, const Color(0xFF9CB0FF)),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: kind == SnackKind.error ? 3 : 2),
        content: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppGap.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
}

/// ── 金额 ──────────────────────────────────────────────
class MoneyText extends StatelessWidget {
  final double amount;
  final bool isExpense;
  final double size;
  final Color? color;
  final bool withSign;
  final bool withSymbol;
  final int decimals;
  final FontWeight weight;

  const MoneyText(
    this.amount, {
    super.key,
    this.isExpense = true,
    this.size = 16,
    this.color,
    this.withSign = false,
    this.withSymbol = true,
    this.decimals = 2,
    this.weight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolved = color ??
        (isExpense ? palette.expense : palette.income);
    final sign = withSign ? (isExpense ? '-' : '+') : '';
    final symbol = withSymbol ? '¥' : '';

    return Text(
      '$sign$symbol${formatMoney(amount, decimals: decimals)}',
      style: moneyStyle(size: size, color: resolved, weight: weight),
    );
  }
}

/// ── 账单行 ────────────────────────────────────────────
///
/// 首页"最近记账"与账单列表共用，保证两处观感一致。
class BillTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback? onTap;
  final bool showChevron;

  const BillTile({
    super.key,
    required this.bill,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // 有备注时标题用备注、副标题补分类；没备注时标题就是分类
    final title = bill.remark.isNotEmpty ? bill.remark : bill.category;
    final subtitle = bill.remark.isNotEmpty
        ? (bill.subcategory.isNotEmpty
            ? '${bill.category} · ${bill.subcategory}'
            : bill.category)
        : bill.subcategory;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppGap.lg, vertical: AppGap.md),
        child: Row(
          children: [
            CategoryIcon(category: bill.category),
            const SizedBox(width: AppGap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppGap.sm),
            MoneyText(
              bill.amount,
              isExpense: bill.isExpense,
              withSign: true,
              size: 16,
            ),
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: palette.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// ── 月份 / 年份切换 ────────────────────────────────────
class PeriodSelector extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onTapLabel;

  const PeriodSelector({
    super.key,
    required this.label,
    this.onPrev,
    this.onNext,
    this.onTapLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget arrow(IconData icon, VoidCallback? onTap) {
      final enabled = onTap != null;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 40,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? palette.textSecondary : palette.textTertiary.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, onPrev),
          InkWell(
            onTap: onTapLabel,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (onTapLabel != null) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: palette.textTertiary),
                  ],
                ],
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, onNext),
        ],
      ),
    );
  }
}
