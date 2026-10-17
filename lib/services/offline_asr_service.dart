import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_model.dart';

/// 离线语音识别（sherpa-onnx + Paraformer 中文模型）
///
/// 全程在本机推理：不联网、不上传录音、不依赖系统识别服务
/// （华为/鸿蒙上没有谷歌语音服务也能用）。
class OfflineAsrService {
  static sherpa.OfflineRecognizer? _recognizer;
  static bool _bindingsReady = false;

  /// 识别器是否已加载（模型文件已就绪且成功创建）
  static bool get isLoaded => _recognizer != null;

  /// 首次调用会加载 native 库并创建识别器，耗时 1~2 秒；
  /// 之后复用同一个实例。
  static Future<void> ensureLoaded([
    AsrModel model = AsrModel.defaultModel,
  ]) async {
    if (_recognizer != null) return;

    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }

    final modelPath = await AsrModelManager.modelPath(model);
    final tokensPath = await AsrModelManager.tokensPath(model);

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(model: modelPath),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );

    _recognizer = sherpa.OfflineRecognizer(config);
  }

  /// 识别一个 WAV 文件（16k 单声道），返回文字；失败返回空串
  static Future<String> transcribe(String wavPath) async {
    await ensureLoaded();
    final recognizer = _recognizer;
    if (recognizer == null) return '';

    final wave = sherpa.readWave(wavPath);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(
        samples: wave.samples,
        sampleRate: wave.sampleRate,
      );
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  /// 释放识别器（退出或切换模型时调用）
  static void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}
