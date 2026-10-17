import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../services/error_reporter.dart';

/// 账单编辑/确认弹窗 — 首页"AI 识别后确认"与账单列表"编辑"共用
///
/// [onSave] 由调用方决定是插入还是更新；弹窗只负责收集表单字段，
/// 保存成功后自动关闭，失败则留在弹窗内提示。
class BillEditSheet extends StatefulWidget {
  final Bill bill;
  final Future<void> Function(Bill) onSave;
  final String title;
  final String saveLabel;

  const BillEditSheet({
    super.key,
    required this.bill,
    required this.onSave,
    this.title = '确认记账',
    this.saveLabel = '确认保存',
  });

  @override
  State<BillEditSheet> createState() => _BillEditSheetState();
}

/// 弹出编辑弹窗（统一的圆角与滚动行为）
Future<void> showBillEditSheet({
  required BuildContext context,
  required Bill bill,
  required Future<void> Function(Bill) onSave,
  String title = '确认记账',
  String saveLabel = '确认保存',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => BillEditSheet(
      bill: bill,
      onSave: onSave,
      title: title,
      saveLabel: saveLabel,
    ),
  );
}

class _BillEditSheetState extends State<BillEditSheet> {
  late String _type;
  late String _category;
  late String _subcategory;
  late double _amount;
  late String _date;
  late String _remark;
  bool _saving = false;

  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();

  List<String> get _availableCategories =>
      _type == '收入' ? ['薪资', '其他'] : BillCategory.categoryNames;

  List<String> get _availableSubcategories =>
      BillCategory.subcategoriesFor(_category);

  @override
  void initState() {
    super.initState();
    _type = widget.bill.type;
    _category = _availableCategories.contains(widget.bill.category)
        ? widget.bill.category
        : _availableCategories.first;
    _subcategory = _availableSubcategories.contains(widget.bill.subcategory)
        ? widget.bill.subcategory
        : '';
    _amount = widget.bill.amount;
    _date = widget.bill.date;
    _remark = widget.bill.remark;

    _amountController.text = _amount > 0 ? _amount.toString() : '';
    _remarkController.text = _remark;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount =
        double.tryParse(_amountController.text.trim()) ?? _amount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请输入有效金额'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);

    final confirmedBill = Bill(
      id: widget.bill.id,
      type: _type,
      category: _category,
      subcategory: _subcategory,
      amount: amount,
      date: _date,
      remark: _remarkController.text.trim(),
      createdAt: widget.bill.createdAt,
    );

    try {
      await widget.onSave(confirmedBill);
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      // 写库失败：留在弹窗内可重试，别让用户以为已保存
      ErrorReporter.report('bill_save', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickDate() async {
    final parts = _date.split('-');
    final initial = DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? DateTime.now().month,
      int.tryParse(parts[2]) ?? DateTime.now().day,
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('zh'),
    );
    if (picked != null) {
      setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            Row(
              children: [
                const Text('类型', style: TextStyle(fontSize: 15)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '支出', label: Text('支出')),
                    ButtonSegment(value: '收入', label: Text('收入')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (sel) => setState(() {
                    _type = sel.first;
                    if (!_availableCategories.contains(_category)) {
                      _category = _availableCategories.first;
                    }
                    _subcategory = '';
                  }),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                const Text('分类', style: TextStyle(fontSize: 15)),
                const Spacer(),
                DropdownButton<String>(
                  value: _category,
                  items: _availableCategories
                      .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${BillCategory.iconFor(c)} $c',
                              style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _category = v;
                        _subcategory = '';
                      });
                    }
                  },
                  underline: const SizedBox(),
                ),
              ],
            ),
            if (_availableSubcategories.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('子分类',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSubcategories.map((name) {
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
            const SizedBox(height: 14),

            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '金额 (¥)',
                prefixIcon: const Icon(Icons.attach_money, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),

            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '日期',
                  prefixIcon: const Icon(Icons.calendar_today, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                child: Text(_date, style: const TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _remarkController,
              decoration: InputDecoration(
                labelText: '备注',
                prefixIcon: const Icon(Icons.note, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Text(widget.saveLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
