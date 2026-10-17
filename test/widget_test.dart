import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_accounting/main.dart';

void main() {
  // 测试环境没有 sqflite 原生插件，用 FFI 实现替代
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App renders home page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // 验证首页 AppBar 标题存在
    expect(find.text('AI 记账'), findsOneWidget);

    // 验证账单列表按钮存在
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);

    // 验证手动记账按钮存在
    expect(find.text('手动记账'), findsOneWidget);
  });
}
