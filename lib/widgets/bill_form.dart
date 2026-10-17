import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import 'app_widgets.dart';

/// 账单表单 —— 手动记账页与"确认/编辑"弹窗共用同一套
///
/// 之前这两处各写了一份表单，改字段要改两遍，样式也会慢慢跑偏。
/// 现在只有这一个实现，字段顺序、分类选择、校验都统一。
class BillForm extends StatefulWidget {
  /// null 表示新建；带 id 表示编辑已有账单
  final Bill? original;
  final String submitLabel;
  final Future<void> Function(Bill) onSubmit;

  /// 手动记账页打开即聚焦金额（弹窗里不聚焦，用户可能先核对分类）
  final bool autofocusAmount;

  const BillForm({
    super.key,
    this.original,
    this.submitLabel = '保存',
    this.autofocusAmount = false,
    required this.onSubmit,
  });

  @override
  State<BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<BillForm> {
  late String _type;
  late String _category;
  late String _subcategory;
  late DateTime _date;
  bool _saving = false;

  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  final _amountFocus = FocusNode();

  List<BillCategory> get _categories => BillCategory.forType(_type);

  List<String> get _subcategories =>
      BillCategory.subcategoriesFor(_category);

  @override
  void initState() {
    super.initState();
    final o = widget.original;

    _type = o?.type ?? '支出';
    final names = _categories.map((c) => c.name).toList();
    _category = (o != null && names.contains(o.category))
        ? o.category
        : names.first;
    _subcategory = (o != null && _subcategories.contains(o.subcategory))
        ? o.subcategory
        : '';
    _date = _parseDate(o?.date) ?? DateTime.now();

    _amountController.text =
        (o != null && o.amount > 0) ? _trimAmount(o.amount) : '';
    _remarkController.text = o?.remark ?? '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  static DateTime? _parseDate(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(text);
    } catch (_) {
      return null;
    }
  }

  /// 去掉多余的 .0（128.0 → 128）
  static String _trimAmount(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  bool get _isYesterday {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return _date.year == y.year && _date.month == y.month && _date.day == y.day;
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

  Future<void> _submit() async {
    if (_saving) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showAppSnack(context, '请先填写金额', kind: SnackKind.error);
      _amountFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final bill = Bill(
      id: widget.original?.id,
      type: _type,
      category: _category,
      subcategory: _subcategory,
      amount: amount,
      date: DateFormat('yyyy-MM-dd').format(_date),
      remark: _remarkController.text.trim(),
      createdAt:
          widget.original?.createdAt ?? DateTime.now().toIso8601String(),
    );

    try {
      await widget.onSubmit(bill);
      // 成功后由调用方负责关闭页面/弹窗
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, '保存失败：$e', kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTypeSwitch(),
        const SizedBox(height: AppGap.lg),

        _buildAmountCard(),
        const SizedBox(height: AppGap.xl),

        _label('分类'),
        const SizedBox(height: AppGap.sm),
        CategoryPicker(
          categories: _categories.map((c) => c.name).toList(),
          selected: _category,
          onSelected: (name) => setState(() {
            _category = name;
            _subcategory = '';
          }),
        ),

        if (_subcategories.isNotEmpty) ...[
          const SizedBox(height: AppGap.xl),
          _label('子分类', trailing: '可不选'),
          const SizedBox(height: AppGap.sm),
          Wrap(
            spacing: AppGap.sm,
            runSpacing: AppGap.sm,
            children: _subcategories.map((name) {
              final selected = _subcategory == name;
              return _Pill(
                label: name,
                selected: selected,
                // 再点一次取消（留空 = 未分类）
                onTap: () =>
                    setState(() => _subcategory = selected ? '' : name),
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: AppGap.xl),
        _label('日期'),
        const SizedBox(height: AppGap.sm),
        Wrap(
          spacing: AppGap.sm,
          runSpacing: AppGap.sm,
          children: [
            _Pill(
              label: '今天',
              selected: _isToday,
              onTap: () => setState(() => _date = DateTime.now()),
            ),
            _Pill(
              label: '昨天',
              selected: _isYesterday,
              onTap: () => setState(() =>
                  _date = DateTime.now().subtract(const Duration(days: 1))),
            ),
            _Pill(
              label: DateFormat('M月d日').format(_date),
              icon: Icons.calendar_today_rounded,
              selected: !_isToday && !_isYesterday,
              onTap: _pickDate,
            ),
          ],
        ),

        const SizedBox(height: AppGap.xl),
        _label('备注'),
        const SizedBox(height: AppGap.sm),
        TextField(
          controller: _remarkController,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: '例如：午餐、打车去公司（可不填）',
            prefixIcon: Icon(Icons.edit_note_rounded,
                size: 20, color: palette.textTertiary),
          ),
        ),

        const SizedBox(height: AppGap.xxl),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }

  Widget _label(String text, {String? trailing}) {
    final palette = context.palette;
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            trailing,
            style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
          ),
        ],
      ],
    );
  }

  /// 支出/收入切换：选中态用语义浅色底，避免主色靛蓝把"收入"也染蓝
  Widget _buildTypeSwitch() {
    final palette = context.palette;

    Widget segment(String value, String label, Color accent, Color soft) {
      final selected = _type == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_type == value) return;
            setState(() {
              _type = value;
              _category = _categories.first.name;
              _subcategory = '';
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? soft : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : palette.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          segment('支出', '支出', palette.expense, palette.expenseSoft),
          segment('收入', '收入', palette.income, palette.incomeSoft),
        ],
      ),
    );
  }

  /// 金额：整张卡就是输入区，数字大、居中、等宽
  Widget _buildAmountCard() {
    final palette = context.palette;
    final accent = _type == '支出' ? palette.expense : palette.income;

    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.lg, vertical: AppGap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '金额',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            autofocus: widget.autofocusAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submit(),
            style: moneyStyle(size: 38, color: accent),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: '¥ 0.00',
              hintStyle: moneyStyle(
                  size: 34, color: palette.textTertiary, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 胶囊标签（子分类 / 日期共用）
class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.brandSoft : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected ? accent : palette.textTertiary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
