import 'package:ai_accounting/widgets/app_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney 金额格式化', () {
    test('两位小数 + 千分位', () {
      expect(formatMoney(1234.5), '1,234.50');
      expect(formatMoney(0), '0.00');
      expect(formatMoney(999.99), '999.99');
      expect(formatMoney(1000), '1,000.00');
      expect(formatMoney(1234567.891), '1,234,567.89');
    });

    test('负数保留符号', () {
      expect(formatMoney(-1234.5), '-1,234.50');
    });

    test('可以关掉千分位 / 指定小数位', () {
      expect(formatMoney(1234.5, grouped: false), '1234.50');
      // 0 位小数会四舍五入：1234.5 → 1235
      expect(formatMoney(1234.5, decimals: 0), '1,235');
      expect(formatMoney(1234.4, decimals: 0), '1,234');
      expect(formatMoney(1234.5, decimals: 1), '1,234.5');
    });
  });
}
