import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_accounting/main.dart';
import 'package:ai_accounting/pages/home_page.dart';
import 'package:ai_accounting/services/app_events.dart';
import 'package:ai_accounting/services/privacy_controller.dart';
import 'package:ai_accounting/widgets/app_widgets.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await PrivacyController.instance.setVisible(false);
    AppEvents.instance.switchTab(0);
  });

  group('moneyDisplay 隐私遮罩', () {
    test('隐藏时用固定长度圆点，不泄露位数', () {
      expect(moneyDisplay(0, visible: false), '¥ ••••');
      expect(moneyDisplay(1234.5, visible: false), '¥ ••••');
      expect(moneyDisplay(12345678.9, visible: false), '¥ ••••');
    });

    test('显示时正常带千分位', () {
      expect(moneyDisplay(1234.5, visible: true), '¥1,234.50');
      expect(moneyDisplay(1234.5, visible: true, decimals: 0), '¥1,235');
    });
  });

  testWidgets('首页默认遮挡本月支出，点眼睛后显示', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final home = find.byType(HomePage);
    expect(
      find.descendant(of: home, matching: find.textContaining('••••')),
      findsWidgets,
      reason: '默认应该遮住金额',
    );

    await tester.tap(find.descendant(
      of: home,
      matching: find.byIcon(Icons.visibility_off_rounded),
    ));
    await tester.pump();

    expect(
      find.descendant(of: home, matching: find.textContaining('••••')),
      findsNothing,
      reason: '点眼睛后应该显示真实金额',
    );
    expect(PrivacyController.instance.amountVisible, isTrue);
    // 点眼睛不应该顺带触发整卡点击（跳去账单页）
    expect(AppEvents.instance.tabIndex.value, 0);
  });

  testWidgets('点本月概览卡进入账单页', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(AppEvents.instance.tabIndex.value, 0);

    await tester.tap(find.text('查看账单明细'));
    await tester.pump();

    expect(AppEvents.instance.tabIndex.value, 1);
  });
}
