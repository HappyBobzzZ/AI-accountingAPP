import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../services/database_service.dart';

/// 手动记账页面 — 直接填写字段保存，无需 AI 解析
class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  String _type = '支出';
  String _category = '餐饮';
  String _subcategory = '';
  DateTime _date = DateTime.now();
  bool _saving = false;

  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  final _amountFocus = FocusNode();

  List<BillCategory> get _categories =>
      _type == '收入' ? BillCategory.incomeCategories : BillCategory.expenseCategories;

  @override
  void initState() {
    super.initState();
    // 金额输入框自动获得焦点，弹出数字键盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _amountFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);
    final bill = Bill(
      type: _type,
      category: _category,
      subcategory: _subcategory,
      amount: amount,
      date: DateFormat('yyyy-MM-dd').format(_date),
      remark: _remarkController.text.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await DatabaseService.instance.insertBill(bill);
    if (!mounted) return;
    Navigator.pop(context, true); // true = 已保存
  }

  void _setQuickDate(int daysAgo) {
    setState(() => _date = DateTime.now().subtract(Duration(days: daysAgo)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('zh'),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = _date.year == today.year && _date.month == today.month && _date.day == today.day;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday = _date.year == yesterday.year && _date.month == yesterday.month && _date.day == yesterday.day;

    return Scaffold(
      appBar: AppBar(title: const Text('手动记账')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── 类型切换 ──────────────────────────────
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '支出', label: Text('支出', style: TextStyle(fontSize: 16))),
                ButtonSegment(value: '收入', label: Text('收入', style: TextStyle(fontSize: 16))),
              ],
              selected: {_type},
              onSelectionChanged: (sel) => setState(() {
                _type = sel.first;
                _category = _categories.first.name;
                _subcategory = '';
              }),
              style: ButtonStyle(
                minimumSize: WidgetStateProperty.all(const Size.fromHeight(44)),
              ),
            ),
            const SizedBox(height: 20),

            // ── 金额 ──────────────────────────────────
            TextField(
              controller: _amountController,
              focusNode: _amountFocus,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '¥ ',
                prefixStyle: const TextStyle(fontSize: 24, color: Colors.grey),
                hintText: '0.00',
                hintStyle: TextStyle(fontSize: 28, color: Colors.grey.shade300),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.blue.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 20),

            // ── 分类 ──────────────────────────────────
            Text('分类', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final selected = _category == c.name;
                return ChoiceChip(
                  avatar: Text(c.icon, style: const TextStyle(fontSize: 16)),
                  label: Text(c.label, style: const TextStyle(fontSize: 14)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _category = c.name;
                    _subcategory = '';
                  }),
                  selectedColor: Colors.blue.shade100,
                  labelStyle: TextStyle(
                    fontSize: 14,
                    color: selected ? Colors.blue.shade900 : Colors.grey.shade800,
                  ),
                );
              }).toList(),
            ),

            // ── 子分类 ──────────────────────────────────
            if (BillCategory.subcategoriesFor(_category).isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('子分类',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BillCategory.subcategoriesFor(_category).map((name) {
                  final selected = _subcategory == name;
                  return ChoiceChip(
                    label: Text(name, style: const TextStyle(fontSize: 13)),
                    selected: selected,
                    // 再点一次可取消（留空 = 未分类）
                    onSelected: (_) =>
                        setState(() => _subcategory = selected ? '' : name),
                    selectedColor: Colors.blue.shade100,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: selected
                          ? Colors.blue.shade900
                          : Colors.grey.shade800,
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),

            // ── 日期 ──────────────────────────────────
            Text('日期', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('今天', style: TextStyle(fontSize: 13)),
                  selected: isToday,
                  onSelected: (_) => _setQuickDate(0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('昨天', style: TextStyle(fontSize: 13)),
                  selected: isYesterday,
                  onSelected: (_) => _setQuickDate(1),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue.shade200),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 15, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('yyyy-MM-dd').format(_date),
                          style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 备注 ──────────────────────────────────
            TextField(
              controller: _remarkController,
              decoration: InputDecoration(
                labelText: '备注（可选）',
                hintText: '例如：午餐、打车去公司…',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.note, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 28),

            // ── 保存 ──────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? '保存中…' : '保存', style: const TextStyle(fontSize: 16)),
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
