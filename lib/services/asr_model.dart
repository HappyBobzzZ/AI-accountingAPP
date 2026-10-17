import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 模型文件（一个模型通常由 onnx + tokens 两个文件组成）
class AsrModelFile {
  final String name;

  /// 下载地址，按顺序尝试（镜像优先，官方兜底）
  final List<String> urls;
  final int bytes;

  const AsrModelFile(this.name, this.urls, this.bytes);
}

/// 语音识别模型清单
class AsrModel {
  final String id;
  final String label;
  final List<AsrModelFile> files;

  const AsrModel({
    required this.id,
    required this.label,
    required this.files,
  });

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);

  int get totalMb => (totalBytes / 1048576).round();

  String get onnxFileName =>
      files.firstWhere((f) => f.name.endsWith('.onnx')).name;

  String get tokensFileName =>
      files.firstWhere((f) => f.name == 'tokens.txt').name;

  /// 默认模型：Paraformer 中文 small（int8 量化，约 78 MB）
  ///
  /// 选它而不是 SenseVoice 的原因：同为 FunASR 家族、专攻中文短句，
  /// 体积只有 SenseVoice int8（237 MB）的三分之一，手机上下载/加载都快得多。
  /// 想换模型只需改这里（SenseVoice 需把下面 paraformer 配置换成 senseVoice）。
  static const paraformerZhSmall = AsrModel(
    id: 'paraformer-zh-small-int8',
    label: 'Paraformer 中文 small',
    files: [
      AsrModelFile(
        'model.int8.onnx',
        [
          'https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/main/model.int8.onnx',
          'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/main/model.int8.onnx',
        ],
        81828675,
      ),
      AsrModelFile(
        'tokens.txt',
        [
          'https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/main/tokens.txt',
          'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09/resolve/main/tokens.txt',
        ],
        75352,
      ),
    ],
  );

  static const defaultModel = paraformerZhSmall;
}

/// 模型下载 / 校验 / 清理
class AsrModelManager {
  /// 模型存放目录：应用私有目录，卸载即清理，不需要存储权限
  static Future<Directory> modelDir([
    AsrModel model = AsrModel.defaultModel,
  ]) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'asr', model.id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> modelPath([
    AsrModel model = AsrModel.defaultModel,
  ]) async =>
      p.join((await modelDir(model)).path, model.onnxFileName);

  static Future<String> tokensPath([
    AsrModel model = AsrModel.defaultModel,
  ]) async =>
      p.join((await modelDir(model)).path, model.tokensFileName);

  /// 模型是否已完整下载（逐个比对文件大小）
  static Future<bool> isReady([
    AsrModel model = AsrModel.defaultModel,
  ]) async {
    final dir = await modelDir(model);
    for (final f in model.files) {
      final file = File(p.join(dir.path, f.name));
      if (!await file.exists()) return false;
      if (await file.length() != f.bytes) return false;
    }
    return true;
  }

  /// 下载模型。返回 true 表示完成，false 表示被取消或失败
  ///
  /// [onProgress] 总进度（已下载字节 / 总字节）
  /// [isCancelled] 返回 true 时中止下载并清理临时文件
  static Future<bool> download({
    AsrModel model = AsrModel.defaultModel,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dir = await modelDir(model);
    final total = model.totalBytes;
    var doneBytes = 0;

    for (final f in model.files) {
      final target = File(p.join(dir.path, f.name));

      // 已完整的文件跳过（支持中途失败后重试）
      if (await target.exists() && await target.length() == f.bytes) {
        doneBytes += f.bytes;
        onProgress?.call(doneBytes, total);
        continue;
      }

      final tmp = File('${target.path}.part');
      Object? lastError;

      // 按顺序尝试镜像 / 官方源
      for (final url in f.urls) {
        final client = http.Client();
        try {
          final response =
              await client.send(http.Request('GET', Uri.parse(url)));
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }

          final sink = tmp.openWrite();
          var received = 0;
          try {
            await for (final chunk in response.stream) {
              if (isCancelled?.call() ?? false) {
                await sink.close();
                if (await tmp.exists()) await tmp.delete();
                return false;
              }
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call(doneBytes + received, total);
            }
          } finally {
            await sink.close();
          }

          // 大小校验：防止镜像返回错误页 / 半截文件
          if (await tmp.length() != f.bytes) {
            throw Exception('${f.name} 大小不符，可能下载中断');
          }
          await tmp.rename(target.path);
          doneBytes += f.bytes;
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (await tmp.exists()) await tmp.delete();
        } finally {
          client.close();
        }
      }

      if (lastError != null) {
        throw Exception('${f.name} 下载失败：$lastError');
      }
    }

    return isReady(model);
  }

  /// 删除已下载模型（设置页里"释放空间"用）
  static Future<void> delete([
    AsrModel model = AsrModel.defaultModel,
  ]) async {
    final dir = await modelDir(model);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
