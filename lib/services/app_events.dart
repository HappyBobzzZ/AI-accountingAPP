import 'package:flutter/foundation.dart';

/// 账单数据变更广播
///
/// 底部导航的四个页面同时存在于 widget 树里（IndexedStack），
/// 首页新增/删除账单后，账单页和统计页必须知道要重新查库，
/// 否则切过去看到的还是旧数据。
class AppEvents extends ChangeNotifier {
  AppEvents._();

  static final AppEvents instance = AppEvents._();

  /// 底部导航当前选中项（0 记账 / 1 账单 / 2 统计 / 3 设置）
  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  void switchTab(int index) => tabIndex.value = index;

  /// 账单有增删改时调用
  void billsChanged() => notifyListeners();
}
