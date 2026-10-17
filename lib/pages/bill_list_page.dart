import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/app_events.dart';
import '../services/data_ops.dart';
import '../services/database_service.dart';
import '../services/error_reporter.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/bill_edit_sheet.dart';

/// 账单列表页 —— 月度汇总 + 按日期分组
class BillListPage extends StatefulWidget {
  const BillListPage({super.key});

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Bill> _bills = [];
  Map<String, double> _summary = {'收入': 0, '支出': 0};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppEvents.instance.addListener(_onBillsChanged);
    _loadData();
  }

  @override
  void dispose() {
    AppEvents.instance.removeListener(_onBillsChanged);
    super.dispose();
  }

  void _onBillsChanged() {
    if (mounted) _loadData();
  }

  String get _yearMonth => DateFormat('yyyy-MM').format(_currentMonth);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _currentMonth.year == now.year && _currentMonth.month == now.month;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = DatabaseService.instance;
      final results = await Future.wait([
        db.getBillsByMonth(_yearMonth),
        db.getMonthlySummary(_yearMonth),
      ]);
      if (!mounted) return;
      setState(() {
        _bills = results[0] as List<Bill>;
        _summary = results[1] as Map<String, double>;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      ErrorReporter.report('bill_list', e, st);
      showAppSnack(context, '加载账单失败，错误已上报电脑', kind: SnackKind.error);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
    });
    _loadData();
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) => _MonthPicker(initial: _currentMonth),
    );
    if (picked == null || !mounted) return;
    setState(() => _currentMonth = DateTime(picked.year, picked.month));
    _loadData();
  }

  Future<void> _deleteBill(Bill bill) async {
    if (bill.id == null) return;
    await DatabaseService.instance.deleteBill(bill.id!);
    AppEvents.instance.billsChanged();
    if (mounted) {
      showAppSnack(
        context,
        '已删除 ${bill.remark.isNotEmpty ? bill.remark : bill.category}',
        kind: SnackKind.success,
      );
    }
  }

  Future<void> _editBill(Bill bill) async {
    if (bill.id == null) return;
    await showBillEditSheet(
      context: context,
      bill: bill,
      title: '编辑账单',
      saveLabel: '保存修改',
      onSave: (edited) async {
        await DatabaseService.instance.updateBill(edited);
        AppEvents.instance.billsChanged();
        if (mounted) showAppSnack(context, '已保存修改', kind: SnackKind.success);
      },
    );
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final income = _summary['收入'] ?? 0;
    final expense = _summary['支出'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          TextButton.icon(
            onPressed: () => exportBillsFlow(context),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('导出'),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.textSecondary,
              textStyle: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: AppGap.sm),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.lg),
            child: _buildSummaryCard(income, expense),
          ),
          const SizedBox(height: AppGap.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PeriodSelector(
                label: DateFormat('yyyy年M月').format(_currentMonth),
                onPrev: () => _shiftMonth(-1),
                onNext: _isCurrentMonth ? null : () => _shiftMonth(1),
                onTapLabel: _pickMonth,
              ),
              if (!_isCurrentMonth) ...[
                const SizedBox(width: AppGap.sm),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(
                          DateTime.now().year, DateTime.now().month);
                    });
                    _loadData();
                  },
                  child: const Text('回到本月'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppGap.xs),
          if (!_loading && _bills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppGap.sm),
              child: Text(
                '点账单可修改 · 左滑删除',
                style: TextStyle(
                    fontSize: 11.5, color: context.palette.textTertiary),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                    ? _buildEmptyState()
                    : _buildBillList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(double income, double expense) {
    final palette = context.palette;
    final balance = income - expense;

    Widget column(String label, String value, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: palette.textTertiary)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: moneyStyle(size: 18, color: color)),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppGap.lg),
      child: Row(
        children: [
          column('支出', '¥${formatMoney(expense)}', palette.expense),
          column('收入', '¥${formatMoney(income)}', palette.income),
          column(
            '结余',
            '${balance < 0 ? '-' : ''}¥${formatMoney(balance.abs())}',
            Theme.of(context).colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.receipt_long_rounded,
      title: '这个月还没有账单',
      subtitle: '回到「记账」，说一句或手动填一笔都行',
      action: SizedBox(
        height: 44,
        child: ElevatedButton(
          onPressed: () => AppEvents.instance.switchTab(0),
          child: const Text('去记一笔'),
        ),
      ),
    );
  }

  Widget _buildBillList() {
    // 按日期分组（后端已按 date DESC 排好，这里保持顺序）
    final grouped = <String, List<Bill>>{};
    for (final bill in _bills) {
      grouped.putIfAbsent(bill.date, () => []).add(bill);
    }
    final dates = grouped.keys.toList();
    final palette = context.palette;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppGap.lg, 0, AppGap.lg, AppGap.xxl),
      itemCount: dates.length,
      itemBuilder: (ctx, i) {
        final date = dates[i];
        final bills = grouped[date]!;
        final dayExpense = bills
            .where((b) => b.isExpense)
            .fold<double>(0, (sum, b) => sum + b.amount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, AppGap.lg, 4, AppGap.sm),
              child: Row(
                children: [
                  Text(
                    _formatDateHeader(date),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (dayExpense > 0)
                    Text(
                      '支出 ¥${formatMoney(dayExpense)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var j = 0; j < bills.length; j++) ...[
                    if (j > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 60,
                        color: palette.hairline,
                      ),
                    _buildSwipeableTile(bills[j]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSwipeableTile(Bill bill) {
    final palette = context.palette;

    return Dismissible(
      key: ValueKey(bill.id ?? bill.hashCode),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppGap.xl),
        color: palette.expense,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('删除',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除这条账单？'),
            content: Text(
              '${bill.remark.isNotEmpty ? bill.remark : bill.category}'
              '　¥${formatMoney(bill.amount)}\n\n删除后无法恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('删除',
                    style: TextStyle(color: palette.expense)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _deleteBill(bill),
      child: BillTile(
        bill: bill,
        showChevron: true,
        onTap: () => _editBill(bill),
      ),
    );
  }

  String _formatDateHeader(String dateStr) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final thatDay = DateTime(dt.year, dt.month, dt.day);

      final label = DateFormat('M月d日').format(dt);
      final weekday = DateFormat('EEEE', 'zh_CN').format(dt);

      if (thatDay == today) return '今天 · $label $weekday';
      if (thatDay == today.subtract(const Duration(days: 1))) {
        return '昨天 · $label $weekday';
      }
      return '$label $weekday';
    } catch (_) {
      return dateStr;
    }
  }
}

/// 月份选择弹层：年份左右切换 + 12 个月网格
class _MonthPicker extends StatefulWidget {
  final DateTime initial;

  const _MonthPicker({required this.initial});

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final selectedMonth =
        (widget.initial.year == _year) ? widget.initial.month : -1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppGap.xl, AppGap.sm, AppGap.xl, AppGap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppGap.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(() => _year--),
                  icon: Icon(Icons.chevron_left_rounded,
                      color: palette.textSecondary),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    '$_year 年',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed:
                      _year >= now.year ? null : () => setState(() => _year++),
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _year >= now.year
                          ? palette.textTertiary.withValues(alpha: 0.4)
                          : palette.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppGap.md),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              childAspectRatio: 2.1,
              mainAxisSpacing: AppGap.sm,
              crossAxisSpacing: AppGap.sm,
              children: List.generate(12, (i) {
                final month = i + 1;
                final isSelected = month == selectedMonth;
                final isFuture = _year == now.year && month > now.month;

                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: isFuture
                      ? null
                      : () => Navigator.pop(
                          context, DateTime(_year, month)),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.brandSoft
                          : palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '$month 月',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isFuture
                            ? palette.textTertiary.withValues(alpha: 0.4)
                            : isSelected
                                ? Theme.of(context).colorScheme.primary
                                : palette.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
