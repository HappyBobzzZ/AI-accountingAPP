import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_accounting/main.dart';

void main() {
  // 测试环境没有 sqflite 原生插件，用 FFI 实现替代
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('主界面渲染底部导航与首页主操作', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // 首页主操作区
    expect(find.text('一句话记账'), findsOneWidget);
    expect(find.text('AI 识别记账'), findsOneWidget);
    expect(find.text('长按说话'), findsOneWidget);
    expect(find.text('手动填写'), findsOneWidget);

    // 底部导航四个标签（标签文字与页面标题会重复出现）
    for (final label in ['记账', '账单', '统计', '设置']) {
      expect(find.text(label), findsWidgets, reason: '缺少「$label」入口');
    }

    // 导航栏本身存在
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
