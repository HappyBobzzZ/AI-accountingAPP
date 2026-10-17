import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// 金额隐私开关
///
/// 首页一打开就是本月支出的大数字，旁边有人瞄一眼就全看见了。
/// 所以默认**隐藏**汇总金额（显示 ¥ ••••），用户点眼睛才显示，
/// 选择会记住。
///
/// 只作用于"汇总数字"（首页概览、账单汇总、统计总览）；
/// 明细列表里的单笔金额始终显示，否则列表就没法看了。
class PrivacyController extends ChangeNotifier {
  PrivacyController._();

  static final PrivacyController instance = PrivacyController._();

  static const _key = 'amount_visible';

  bool _amountVisible = false;
  bool get amountVisible => _amountVisible;

  Future<void> load() async {
    await Prefs.load();
    _amountVisible = Prefs.getBool(_key, fallback: false);
    notifyListeners();
  }

  Future<void> toggle() async {
    _amountVisible = !_amountVisible;
    notifyListeners();
    await Prefs.setBool(_key, _amountVisible);
  }

  Future<void> setVisible(bool value) async {
    if (_amountVisible == value) return;
    _amountVisible = value;
    notifyListeners();
    await Prefs.setBool(_key, value);
  }
}
