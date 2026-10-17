import 'package:flutter/foundation.dart';

import 'asr_model.dart';

/// 语音模型状态（下载进度、是否就绪）
///
/// 首页长按麦克风和设置页的"模型管理"都要看这份状态，
/// 抽成单例后两边共用同一个下载任务，不会各下一遍。
class AsrModelController extends ChangeNotifier {
  AsrModelController._();

  static final AsrModelController instance = AsrModelController._();

  bool _checked = false;
  bool _ready = false;
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  bool get checked => _checked;
  bool get ready => _ready;
  bool get downloading => _downloading;
  double get progress => _progress;
  String? get error => _error;

  AsrModel get model => AsrModel.defaultModel;

  /// 查一次模型文件是否完整（首次调用后走缓存）
  Future<bool> ensureChecked({bool force = false}) async {
    if (_checked && !force) return _ready;
    try {
      _ready = await AsrModelManager.isReady();
    } catch (_) {
      // 单元测试环境没有 path_provider 插件，按"未就绪"处理即可
      _ready = false;
    }
    _checked = true;
    notifyListeners();
    return _ready;
  }

  /// 下载模型，返回是否成功
  Future<bool> download() async {
    if (_downloading) return false;

    _downloading = true;
    _progress = 0;
    _error = null;
    notifyListeners();

    try {
      var lastShown = 0.0;
      final ok = await AsrModelManager.download(
        onProgress: (received, total) {
          if (total <= 0) return;
          final p = received / total;
          // 每 1% 才刷新，避免高频 rebuild
          if (p - lastShown >= 0.01 || p >= 1) {
            lastShown = p;
            _progress = p;
            notifyListeners();
          }
        },
      );
      _ready = ok;
      _checked = true;
      return ok;
    } catch (e) {
      _error = '$e';
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// 删除已下载的模型，释放空间
  Future<void> remove() async {
    await AsrModelManager.delete();
    _ready = false;
    _checked = true;
    _progress = 0;
    notifyListeners();
  }
}
