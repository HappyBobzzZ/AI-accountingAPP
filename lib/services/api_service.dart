import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/bill.dart';
import 'local_parser_service.dart';

/// API 服务 — 优先连接 PC 后端，不可达时自动使用本地引擎
class ApiService {
  // 电脑局域网 IP（手机和电脑需在同一网络）
  static const String baseUrl = 'http://192.168.2.146:8000';

  /// 上次连接状态（用于 UI 提示）
  static bool lastUsedRemote = false;

  /// 检查远程服务器是否可用
  static Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['model_loaded'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 从 PC 后端获取导入账单列表
  static Future<List<Bill>?> fetchImportBills() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/import/csv'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final billsJson = data['bills'] as List<dynamic>;
        return billsJson
            .map((j) => Bill.fromApiResponse(j as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 解析记账文本
  /// - WiFi 环境：调用 PC 后端（NLP 更准确）
  /// - 非 WiFi 环境：自动降级到本地正则引擎
  static Future<Bill> extractBill(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('输入文本不能为空');
    }

    // 先尝试远程（3 秒快速超时）
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/extract'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'text': text.trim()}),
          )
          .timeout(const Duration(seconds: 3));

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        lastUsedRemote = true;
        return Bill.fromApiResponse(data);
      }
    } on SocketException {
      // 服务器不可达 → 降级到本地
    } on http.ClientException {
      // 网络错误 → 降级到本地
    } on Exception {
      // 超时或其他错误 → 降级到本地
    }

    // 降级：使用本地正则引擎
    lastUsedRemote = false;
    return LocalParserService.parse(text.trim());
  }
}
