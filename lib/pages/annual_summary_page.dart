import 'package:flutter/material.dart';
import '../services/database_service.dart';

/// 年度汇总页面
class AnnualSummaryPage extends StatefulWidget {
  const AnnualSummaryPage({super.key});

  @override
  State<AnnualSummaryPage> createState() => _AnnualSummaryPageState();
}

class _AnnualSummaryPageState extends State<AnnualSummaryPage> {
  int _year = DateTime.now().year;
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DatabaseService.instance.getYearlySummary(_year);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  void _prevYear() => setState(() { _year--; _load(); });
  void _nextYear() => setState(() { _year++; _load(); });

  @override
  Widget build(BuildContext context) {
    final isCurrentYear = _year == DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: const Text('年度汇总'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('暂无数据'))
              : _buildContent(isCurrentYear),
    );
  }

  Widget _buildContent(bool isCurrentYear) {
    final totalIncome = (_data!['totalIncome'] as double?) ?? 0;
    final totalExpense = (_data!['totalExpense'] as double?) ?? 0;
    final balance = (_data!['balance'] as double?) ?? 0;
    final monthly = (_data!['monthly'] as Map<int, Map<String, double>>?) ?? {};

    // 找出最大值用于条形图比例
    double maxVal = 0;
    for (final m in monthly.values) {
      final v = (m['支出'] ?? 0) + (m['收入'] ?? 0);
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = 1;

    return Column(
      children: [
        // ── 年度总览卡片 ───────────────────────────────
        _buildOverviewCard(totalIncome, totalExpense, balance),

        // ── 年份切换 ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevYear),
              Text('$_year 年',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: isCurrentYear ? null : _nextYear,
              ),
            ],
          ),
        ),

        // ── 月明细标题 ─────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.bar_chart, size: 18, color: Colors.blueGrey),
              SizedBox(width: 6),
              Text('月度明细', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const Divider(),

        // ── 月度条形图 ─────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 12,
            itemBuilder: (ctx, i) {
              final month = i + 1;
              final data = monthly[month] ?? {'收入': 0.0, '支出': 0.0};
              final income = data['收入'] ?? 0;
              final expense = data['支出'] ?? 0;
              final total = income + expense;
              final hasData = total > 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    // 月份标签
                    SizedBox(
                      width: 36,
                      child: Text('$month月',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ),

                    // 条形图
                    Expanded(
                      child: hasData
                          ? LayoutBuilder(builder: (ctx, constraints) {
                              final maxW = constraints.maxWidth;
                              final expenseW = (expense / maxVal) * maxW * 0.7;
                              final incomeW = (income / maxVal) * maxW * 0.7;
                              return Row(
                                children: [
                                  if (expenseW > 2)
                                    Container(
                                      height: 22,
                                      width: expenseW,
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade300,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  if (expenseW > 2 && incomeW > 2)
                                    const SizedBox(width: 4),
                                  if (incomeW > 2)
                                    Container(
                                      height: 22,
                                      width: incomeW,
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade300,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                ],
                              );
                            })
                          : Container(
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                    ),

                    // 金额数字
                    SizedBox(
                      width: 80,
                      child: hasData
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (expense > 0)
                                  Text('支出 ¥${expense.toStringAsFixed(0)}',
                                      style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                                if (income > 0)
                                  Text('收入 ¥${income.toStringAsFixed(0)}',
                                      style: TextStyle(fontSize: 11, color: Colors.green.shade500)),
                              ],
                            )
                          : Text('-',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCard(double income, double expense, double balance) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text('$_year 年总览',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('总收入', income, Colors.greenAccent.shade100),
              Container(width: 1, height: 36, color: Colors.white30),
              _buildStat('总支出', expense, Colors.redAccent.shade100),
              Container(width: 1, height: 36, color: Colors.white30),
              _buildStat('结余', balance.abs(),
                  balance >= 0 ? Colors.white : Colors.redAccent.shade200,
                  prefix: balance < 0 ? '-' : ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, double amount, Color color, {String prefix = ''}) {
    return Flexible(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$prefix¥${amount.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
