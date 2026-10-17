import 'package:flutter/material.dart';

import '../services/app_events.dart';
import '../theme/app_theme.dart';
import 'annual_summary_page.dart';
import 'bill_list_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

/// 应用主壳：底部四个标签
///
/// 之前"账单列表""年度汇总"藏在首页 AppBar 的两个裸图标里，新用户
/// 根本猜不到；导入导出更是只有一个 download 图标。现在全部改成
/// 看得见文字的标签页，AppBar 只留页面自己的操作。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 用 IndexedStack 保活：切回来不会丢月份、滚动位置
  static const _pages = <Widget>[
    HomePage(),
    BillListPage(),
    AnnualSummaryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ValueListenableBuilder<int>(
      valueListenable: AppEvents.instance.tabIndex,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.hairline, width: 1)),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: AppEvents.instance.switchTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.edit_outlined),
                selectedIcon: Icon(Icons.edit_rounded),
                label: '记账',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: '账单',
              ),
              NavigationDestination(
                icon: Icon(Icons.insert_chart_outlined_rounded),
                selectedIcon: Icon(Icons.insert_chart_rounded),
                label: '统计',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
