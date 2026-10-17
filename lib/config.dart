/// 全局配置
///
/// 这个 App 是「单机优先」的：没有电脑后端也能完整使用，
/// 解析会自动降级到本地正则引擎。
///
/// 只有在同一个 WiFi 下、且电脑上跑着 `server_simple.py` 时，
/// 才会用到这些依赖后端的可选能力：
/// - 云端 AI 解析（比本地正则准）
/// - 从电脑导入历史账单
/// - 真机异常上报（排查用）
class AppConfig {
  AppConfig._();

  /// 电脑端后端地址。
  ///
  /// 换电脑或换网段时改这里的默认值，或者不改代码、编译时覆盖：
  /// ```
  /// flutter build apk --release --target-platform android-arm64 \
  ///   --dart-define=BACKEND_URL=http://192.168.1.10:8000
  /// ```
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://192.168.2.146:8000',
  );

  /// 后端相关接口前缀
  static String get apiBase => backendUrl;
}
