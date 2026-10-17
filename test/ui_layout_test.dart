import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_accounting/main.dart';
import 'package:ai_accounting/models/bill.dart';
import 'package:ai_accounting/pages/manual_entry_page.dart';
import 'package:ai_accounting/theme/app_theme.dart';
import 'package:ai_accounting/widgets/bill_form.dart';

/// 布局回归：在手机尺寸下把所有页面过一遍。
/// Flutter 的溢出（RenderFlex overflowed）会作为异常抛出，
/// 测试会直接失败，比自己盯截图靠谱。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> setPhoneSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('四个标签页在手机尺寸下不溢出', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final navBar = find.byType(NavigationBar);
    for (final label in ['账单', '统计', '设置', '记账']) {
      await tester.tap(
        find.descendant(of: navBar, matching: find.text(label)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('手动记账页在手机尺寸下不溢出', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const ManualEntryPage(),
    ));
    await tester.pump();

    expect(find.text('手动记账'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账单表单在深色主题下可用', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: BillForm(
            original: Bill(
              id: 1,
              type: '支出',
              category: '餐饮',
              subcategory: '三餐',
              amount: 128.5,
              date: '2026-10-17',
              remark: '午饭',
              createdAt: '2026-10-17T12:00:00',
            ),
            onSubmit: (_) async {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('128.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
