import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// WAV 头信息（只关心离线识别需要的字段）
class WavFormat {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  const WavFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  int get bytesPerSample => bitsPerSample ~/ 8;

  /// 音频时长（秒）
  double get durationSec =>
      dataLength / (bytesPerSample * channels * sampleRate);
}

/// 一段录音的人声分析结果
///
/// 为什么要做这件事：Paraformer 这类端到端模型在纯静音/环境噪声上
/// 不会输出空串，而是"脑补"出一段莫名其妙的话（幻听）。
/// 所以送进模型之前先用能量检测判断到底有没有人在说话。
class VoiceActivity {
  /// 低于这个时长认为没说完整（正常一句账单 1~3 秒）
  static const double minDurationSec = 0.25;

  /// 峰值低于 -45 dBFS 认为是静音（16bit 下振幅约 184，远低于正常说话）
  static const double minPeakDbfs = -45.0;

  /// 有声帧占比下限。纯噪声的帧能量几乎一样平，占比接近 0
  static const double minVoicedRatio = 0.04;

  final double durationSec;

  /// 整段录音的峰值电平
  final double peakDbfs;

  /// 噪声底（各帧能量的 20% 分位）
  final double noiseDbfs;

  /// 判为"有声"的门槛：噪声底 + 8dB 与绝对下限取高者
  final double thresholdDbfs;

  /// 超过门槛的帧占比
  final double voicedRatio;

  const VoiceActivity({
    required this.durationSec,
    required this.peakDbfs,
    required this.noiseDbfs,
    required this.thresholdDbfs,
    required this.voicedRatio,
  });

  bool get tooShort => durationSec < minDurationSec;

  /// 是否检测到人声
  bool get hasSpeech =>
      !tooShort && peakDbfs > minPeakDbfs && voicedRatio >= minVoicedRatio;

  /// 没检测到人声时给用户的提示
  String get hint => tooShort
      ? '说话时间太短了，长按麦克风多说一会儿'
      : '没听到人声，长按麦克风再说一次';
}

/// WAV 解析 + 人声检测（纯函数，可单测）
class VoiceDetector {
  /// 分析一个 WAV 文件。
  ///
  /// 返回 null 表示无法判断（不是 WAV / 不是 16bit），调用方应直接走识别。
  static Future<VoiceActivity?> analyzeFile(String path) async {
    try {
      return analyzeBytes(await File(path).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// 解析 RIFF/WAVE 头；失败返回 null
  static WavFormat? parseWavFormat(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (_fourCC(bytes, 0) != 'RIFF' || _fourCC(bytes, 8) != 'WAVE') return null;

    final data = ByteData.sublistView(bytes);
    int? sampleRate, channels, bits;
    int? dataOffset, dataLength;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = _fourCC(bytes, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (id == 'fmt ' && body + 16 <= bytes.length) {
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data' && dataOffset == null) {
        dataOffset = body;
        // 边录边写的 WAV 会把 size 写成 0 或 0xFFFFFFFF，用实际长度兜底
        final available = bytes.length - body;
        dataLength = (size == 0 || size > available) ? available : size;
      }

      if (sampleRate != null && dataOffset != null) break;

      // chunk 按偶数字节对齐
      var next = body + size;
      if (size.isOdd) next += 1;
      if (next <= offset) break; // 防死循环（size 为 0 的坏文件）
      offset = next;
    }

    if (sampleRate == null ||
        channels == null ||
        bits == null ||
        dataOffset == null ||
        dataLength == null) {
      return null;
    }
    if (sampleRate <= 0 || channels <= 0 || bits <= 0 || dataLength <= 0) {
      return null;
    }

    return WavFormat(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bits,
      dataOffset: dataOffset,
      dataLength: dataLength,
    );
  }

  /// 逐帧算能量，判断有没有人声
  static VoiceActivity? analyzeBytes(Uint8List bytes) {
    final fmt = parseWavFormat(bytes);
    // 只处理 16bit PCM（record 的 wav 编码就是这个）；其它格式不做判断
    if (fmt == null || fmt.bitsPerSample != 16) return null;

    final pcm = ByteData.sublistView(
      bytes,
      fmt.dataOffset,
      fmt.dataOffset + fmt.dataLength,
    );
    final frameBytes = 2 * fmt.channels;
    final totalSamples = fmt.dataLength ~/ frameBytes;
    final frameSamples = math.max(1, (fmt.sampleRate * 0.025).round());
    final frameCount = totalSamples ~/ frameSamples;

    if (frameCount < 1) {
      return VoiceActivity(
        durationSec: fmt.durationSec,
        peakDbfs: -120,
        noiseDbfs: -120,
        thresholdDbfs: -50,
        voicedRatio: 0,
      );
    }

    var peak = 0;
    final frameDb = Float64List(frameCount);
    for (var f = 0; f < frameCount; f++) {
      var sumSq = 0.0;
      final start = f * frameSamples;
      for (var i = 0; i < frameSamples; i++) {
        final s = pcm.getInt16((start + i) * frameBytes, Endian.little);
        final a = s.abs();
        if (a > peak) peak = a;
        sumSq += s * s;
      }
      final rms = math.sqrt(sumSq / frameSamples);
      frameDb[f] = _db(rms);
    }

    // 噪声底：把帧能量排序取 20% 分位，比固定阈值更抗设备增益差异
    final sorted = List<double>.from(frameDb)..sort();
    final noiseIndex = math.max(0, (sorted.length * 0.2).floor() - 1);
    final noiseDb = sorted[noiseIndex];
    final threshold = math.max(noiseDb + 8, -50.0);

    var voiced = 0;
    for (final db in frameDb) {
      if (db > threshold) voiced++;
    }

    return VoiceActivity(
      durationSec: fmt.durationSec,
      peakDbfs: _db(peak.toDouble()),
      noiseDbfs: noiseDb,
      thresholdDbfs: threshold,
      voicedRatio: voiced / frameCount,
    );
  }

  /// 线性幅度 → dBFS（满刻度 32768）
  static double _db(double amplitude) {
    if (amplitude <= 1e-6) return -120;
    return 20 * (math.log(amplitude / 32768) / math.ln10);
  }

  static String _fourCC(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
}
