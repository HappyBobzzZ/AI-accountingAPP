import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../services/app_events.dart';
import '../services/database_service.dart';
import '../services/privacy_controller.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import '../widgets/app_widgets.dart';

/// 统计页 —— 年度总览 + 月度收支 + 支出分类占比
class AnnualSummaryPage extends StatefulWidget {
  const AnnualSummaryPage({super.key});

  @override
  State<AnnualSummaryPage> createState() => _AnnualSummaryPageState();
}

class _AnnualSummaryPageState extends State<AnnualSummaryPage> {
  int _year = DateTime.now().year;
  Map<String, dynamic>? _data;
  List<Bill> _bills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppEvents.instance.addListener(_onBillsChanged);
    _load();
  }

  @override
  void dispose() {
    AppEvents.instance.removeListener(_onBillsChanged);
    super.dispose();
  }

  void _onBillsChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await DatabaseService.instance.getYearlySummary(_year);
      final bills = await DatabaseService.instance.getBillsByYear(_year);
      if (!mounted) return;
      setState(() {
        _data = data;
        _bills = bills;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isCurrentYear => _year == DateTime.now().year;

  void _shiftYear(int delta) {
    setState(() => _year += delta);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppGap.lg, AppGap.sm, AppGap.lg, AppGap.xxl),
              children: [
                _buildOverviewCard(),
                const SizedBox(height: AppGap.md),
                Center(
                  child: PeriodSelector(
                    label: '$_year 年',
                    onPrev: () => _shiftYear(-1),
                    onNext: _isCurrentYear ? null : () => _shiftYear(1),
                  ),
                ),
                const SizedBox(height: AppGap.xl),
                _buildMonthlySection(),
                const SizedBox(height: AppGap.xl),
                _buildCategorySection(),
              ],
            ),
    );
  }

  Widget _buildOverviewCard() {
    final income = (_data?['totalIncome'] as double?) ?? 0;
    final expense = (_data?['totalExpense'] as double?) ?? 0;
    final balance = income - expense;

    return AnimatedBuilder(
      animation: PrivacyController.instance,
      builder: (context, _) {
        final visible = PrivacyController.instance.amountVisible;

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A55E0), Color(0xFF6C86FF)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  top: -40,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppGap.xl, AppGap.lg, AppGap.xl, AppGap.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_year 年总支出',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xCCFFFFFF)),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          moneyDisplay(expense, visible: visible),
                          style: moneyStyle(
                              size: 32,
                              color: Colors.white,
                              letterSpacing: -0.8),
                        ),
                      ),
                      const SizedBox(height: AppGap.lg),
                      Row(
                        children: [
                          _miniStat('总收入', income, visible),
                          const SizedBox(width: AppGap.xl),
                          _miniStat('结余', balance, visible),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, double value, bool visible) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xB3FFFFFF))),
        const SizedBox(width: 6),
        Text(
          moneyDisplay(value, visible: visible),
          style: moneyStyle(
              size: 14, color: Colors.white, weight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMonthlySection() {
    final monthly =
        (_data?['monthly'] as Map<int, Map<String, double>>?) ?? {};
    final palette = context.palette;

    var maxVal = 0.0;
    for (final m in monthly.values) {
      final v = m['支出'] ?? 0;
      if (v > maxVal) maxVal = v;
    }
    if (maxVal <= 0) maxVal = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppGap.sm),
          child: Row(
            children: [
              Text(
                '月度支出',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              _legendDot(palette.expense, '支出'),
              const SizedBox(width: AppGap.md),
              _legendDot(palette.income, '收入'),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: AppGap.lg, vertical: AppGap.md),
          child: Column(
            children: [
              for (var i = 0; i < 12; i++)
                _buildMonthRow(
                  month: i + 1,
                  expense: monthly[i + 1]?['支出'] ?? 0,
                  income: monthly[i + 1]?['收入'] ?? 0,
                  maxVal: maxVal,
                  isLast: i == 11,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11.5, color: context.palette.textTertiary)),
      ],
    );
  }

  Widget _buildMonthRow({
    required int month,
    required double expense,
    required double income,
    required double maxVal,
    required bool isLast,
  }) {
    final palette = context.palette;
    final hasData = expense > 0 || income > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppGap.md),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$month月',
              style: TextStyle(fontSize: 12, color: palette.textTertiary),
            ),
          ),
          Expanded(
            child: hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(expense / maxVal, palette.expense),
                      if (income > 0) ...[
                        const SizedBox(height: 3),
                        _bar(income / maxVal, palette.income),
                      ],
                    ],
                  )
                : Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
          ),
          const SizedBox(width: AppGap.md),
          // 收入和支出都显示：只看支出看不出"这个月其实有进账"
          SizedBox(
            width: 96,
            height: 32,
            child: hasData
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (expense > 0)
                        _amountLine('支出', expense, palette.expense),
                      if (income > 0)
                        _amountLine('收入', income, palette.income),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '—',
                      style: TextStyle(
                          fontSize: 11.5, color: palette.textTertiary),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _amountLine(String label, double value, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        '$label ¥${formatMoney(value, decimals: 0)}',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.3,
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _bar(double ratio, Color color) {
    final clamped = ratio.clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: constraints.maxWidth * clamped,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCategorySection() {
    final palette = context.palette;

    final byCategory = <String, double>{};
    for (final bill in _bills) {
      if (!bill.isExpense) continue;
      byCategory.update(bill.category, (v) => v + bill.amount,
          ifAbsent: () => bill.amount);
    }
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppGap.sm),
          child: Text(
            '支出分类',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: AppGap.lg, vertical: AppGap.md),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppGap.lg),
                  child: Center(
                    child: Text(
                      '$_year 年还没有支出记录',
                      style: TextStyle(
                          fontSize: 13, color: palette.textTertiary),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _buildCategoryRow(
                        entries[i].key,
                        entries[i].value,
                        total,
                        isLast: i == entries.length - 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryRow(String category, double amount, double total,
      {bool isLast = false}) {
    final palette = context.palette;
    final ratio = total <= 0 ? 0.0 : amount / total;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppGap.lg),
      child: Row(
        children: [
          CategoryIcon(category: category, size: 34),
          const SizedBox(width: AppGap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '¥${formatMoney(amount, decimals: 0)}',
                      style: moneyStyle(
                          size: 13.5,
                          color: palette.textSecondary,
                          weight: FontWeight.w600),
                    ),
                    const SizedBox(width: AppGap.sm),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${(ratio * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5, color: palette.textTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: palette.surfaceAlt,
                    color: CategoryStyle.iconColor(context, category),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
