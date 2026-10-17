import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../services/database_service.dart';
import '../services/error_reporter.dart';
import '../services/export_service.dart';
import '../widgets/bill_edit_sheet.dart';
import 'annual_summary_page.dart';

/// 账单列表页 — 月度汇总 + 按日期分组的账单列表
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
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _yearMonth =>
      DateFormat('yyyy-MM').format(_currentMonth);

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = DatabaseService.instance;
      final results = await Future.wait([
        db.getBillsByMonth(_yearMonth),
        db.getMonthlySummary(_yearMonth),
      ]);
      if (mounted) {
        setState(() {
          _bills = results[0] as List<Bill>;
          _summary = results[1] as Map<String, double>;
          _loading = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() => _loading = false);
        ErrorReporter.report('bill_list', e, st);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载账单失败，错误已上报电脑')),
        );
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('加载账单失败'),
            content: SingleChildScrollView(
              child: SelectableText(e.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _prevMonth() {
    setState(() {
      _currentMonth =
          DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadData();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth =
          DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _loadData();
  }

  Future<void> _deleteBill(Bill bill) async {
    if (bill.id == null) return;
    await DatabaseService.instance.deleteBill(bill.id!);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除: ${bill.remark.isNotEmpty ? bill.remark : bill.category} ¥${bill.amount}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 导出全部账单为 CSV，再交给系统分享面板
  Future<void> _exportBills() async {
    if (_exporting) return;

    final bills = await DatabaseService.instance.getAllBills();
    if (!mounted) return;
    if (bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有账单可以导出')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出账单备份'),
        content: Text(
          '将把全部 ${bills.length} 条账单导出为 CSV 文件，'
          '可用 Excel / WPS 打开。\n\n'
          '点"导出"后会弹出分享面板，可保存到文件管理器、'
          '发到微信或邮箱。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _exporting = true);
    try {
      // iPad/Mac 需要锚点，安卓忽略
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await ExportService.shareCsv(bills, sharePositionOrigin: origin);
    } catch (e, st) {
      ErrorReporter.report('export_csv', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 点击账单 → 弹出编辑弹窗，保存后刷新列表
  Future<void> _editBill(Bill bill) async {
    if (bill.id == null) return;
    await showBillEditSheet(
      context: context,
      bill: bill,
      title: '编辑账单',
      saveLabel: '保存修改',
      onSave: (edited) async {
        await DatabaseService.instance.updateBill(edited);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 已保存修改'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
    );
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final income = _summary['收入'] ?? 0;
    final expense = _summary['支出'] ?? 0;
    final balance = income - expense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单列表'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            tooltip: '导出账单备份',
            onPressed: _exporting ? null : _exportBills,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_view_month),
            tooltip: '年度汇总',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AnnualSummaryPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 月度汇总卡片
          _buildSummaryCard(income, expense, balance),

          // 月份切换
          _buildMonthSelector(),

          // 账单列表
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

  Widget _buildSummaryCard(double income, double expense, double balance) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('收入', income, Colors.greenAccent.shade100),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildSummaryItem('支出', expense, Colors.redAccent.shade100),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildSummaryItem('结余', balance.abs(),
              balance >= 0 ? Colors.white : Colors.redAccent.shade200,
              prefix: balance < 0 ? '-' : ''),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color,
      {String prefix = ''}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '$prefix¥${amount.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    final monthLabel = DateFormat('yyyy年M月').format(_currentMonth);
    final now = DateTime.now();
    final isCurrentMonth =
        _currentMonth.year == now.year && _currentMonth.month == now.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
          ),
          Text(
            monthLabel,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth ? null : _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('还没有账单',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('回到首页，输入一句话即可记账',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildBillList() {
    // 按日期分组
    final grouped = <String, List<Bill>>{};
    for (final bill in _bills) {
      grouped.putIfAbsent(bill.date, () => []).add(bill);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: dateKeys.length,
      itemBuilder: (ctx, groupIdx) {
        final date = dateKeys[groupIdx];
        final bills = grouped[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日期分组头
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _formatDateHeader(date),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 同日的账单
            ...bills.map((bill) => _buildBillTile(bill)),
          ],
        );
      },
    );
  }

  String _formatDateHeader(String dateStr) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final thatDay = DateTime(dt.year, dt.month, dt.day);

      final label = DateFormat('M月d日').format(dt);
      final weekday =
          DateFormat('EEEE', 'zh_CN').format(dt);

      if (thatDay == today) {
        return '今天  $label  $weekday';
      } else if (thatDay == today.subtract(const Duration(days: 1))) {
        return '昨天  $label  $weekday';
      } else {
        return '$label  $weekday';
      }
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildBillTile(Bill bill) {
    return Dismissible(
      key: ValueKey(bill.id ?? bill.hashCode),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认删除'),
            content: Text(
                '删除这条账单？\n${bill.remark.isNotEmpty ? bill.remark : bill.category} ¥${bill.amount}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red),
                child: const Text('删除', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _deleteBill(bill),
      child: ListTile(
        onTap: () => _editBill(bill),
        leading: CircleAvatar(
          backgroundColor: bill.isExpense
              ? Colors.red.shade50
              : Colors.green.shade50,
          child: Text(
            BillCategory.iconFor(bill.category),
            style: const TextStyle(fontSize: 22),
          ),
        ),
        title: Text(
          bill.remark.isNotEmpty ? bill.remark : bill.category,
          style: const TextStyle(fontSize: 15),
        ),
        subtitle: Text(
          bill.subcategory.isNotEmpty
              ? '${bill.category} · ${bill.subcategory}'
              : bill.category,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${bill.isExpense ? "-" : "+"}¥${bill.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: bill.isExpense ? Colors.red : Colors.green,
              ),
            ),
            // 提示该行可点击编辑
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
