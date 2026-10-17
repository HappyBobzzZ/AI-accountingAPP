import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// 异常上报 — 把手机端异常 POST 回电脑端服务器（排查真机错误）
/// fire-and-forget，绝不抛出、绝不影响主流程
class ErrorReporter {
  static String get _endpoint => '${AppConfig.apiBase}/api/log';

  static void report(String source, Object error, StackTrace stack) {
    try {
      http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'source': source,
              'error': error.toString(),
              'stack': stack.toString(),
            }),
          )
          .timeout(const Duration(seconds: 3))
          .onError((_, _) => http.Response('', 500)); // 上报失败静默，不打扰用户
    } catch (_) {}
  }
}
