import 'package:flutter/services.dart';

/// 触感反馈
///
/// 为什么不直接用 [HapticFeedback]：Flutter 的 HapticFeedback 走的是
/// View.performHapticFeedback()，它受系统"触感反馈"开关控制，且
/// mediumImpact 映射到的 CONTEXT_CLICK 在不少华为/鸿蒙机型上完全没效果
/// （调用不报错，就是不震）。这里直接调原生 Vibrator 服务，绕开这层。
class Haptics {
  static const MethodChannel _channel = MethodChannel('ai_accounting/haptic');

  /// 原生通道不可用时置 false，后续直接走 Flutter 兜底，不再反复尝试
  static bool _nativeAvailable = true;

  /// 轻震一下（约 30ms），用于"长按生效/开始录音"这类提示
  static Future<void> tap({int ms = 30}) async {
    if (_nativeAvailable) {
      try {
        final ok = await _channel.invokeMethod<bool>('vibrate', {'ms': ms});
        if (ok == true) return;
        // 返回 false = 设备没有振动器，没必要再试原生
        _nativeAvailable = false;
      } on MissingPluginException {
        _nativeAvailable = false;
      } catch (_) {
        _nativeAvailable = false;
      }
    }
    try {
      // heavyImpact 在 Android 上映射到 LONG_PRESS，是各家 ROM 支持最好的一个
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // 没有振动器（平板/模拟器）时静默忽略
    }
  }
}
