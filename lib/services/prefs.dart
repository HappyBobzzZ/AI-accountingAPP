import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 极简本地偏好存储（一个 JSON 文件）
///
/// 没有引入 shared_preferences：这台机器上的包最终要跑在鸿蒙兼容层，
/// 每多一个原生插件就多一处可能加载失败的地方。path_provider 已经在用、
/// 已经验证可用，直接拿它写文件最稳。
class Prefs {
  Prefs._();

  static Map<String, dynamic> _cache = {};
  static File? _file;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/prefs.json');
      _file = file;
      if (await file.exists()) {
        final decoded = json.decode(await file.readAsString());
        if (decoded is Map<String, dynamic>) _cache = decoded;
      }
    } catch (_) {
      // 读不到就当全是默认值（测试环境没有 path_provider 也会走这里）
    }
  }

  static bool getBool(String key, {bool fallback = false}) {
    final value = _cache[key];
    return value is bool ? value : fallback;
  }

  static Future<void> setBool(String key, bool value) async {
    _cache[key] = value;
    try {
      await _file?.writeAsString(json.encode(_cache));
    } catch (_) {}
  }
}
