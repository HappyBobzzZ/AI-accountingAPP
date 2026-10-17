import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_accounting/services/voice_activity.dart';
import 'package:flutter_test/flutter_test.dart';

const int _rate = 16000;

/// 造一段 16bit PCM 的 WAV
Uint8List _wav(
  List<int> samples, {
  int sampleRate = _rate,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final dataLen = samples.length * bytesPerSample * channels;
  final out = ByteData(44 + dataLen);

  void writeStr(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeStr(0, 'RIFF');
  out.setUint32(4, 36 + dataLen, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk 大小
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  out.setUint16(32, channels * bytesPerSample, Endian.little);
  out.setUint16(34, bitsPerSample, Endian.little);
  writeStr(36, 'data');
  out.setUint32(40, dataLen, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final off = 44 + i * bytesPerSample;
    if (off + 2 > out.lengthInBytes) break;
    out.setInt16(off, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// 模拟说话：带音节包络的浊音
///
/// 真人说话一定有起伏（每秒 3~5 个音节，音节之间还有停顿），
/// 纯正弦波不像人声，也测不出"能量是否有起伏"这条判据。
List<int> _speech(double seconds, double amplitude, {int freq = 220}) {
  final n = (seconds * _rate).round();
  return List<int>.generate(n, (i) {
    final t = i / _rate;
    final pos = (t * 4) % 1.0; // 每秒 4 个音节
    final env = pos < 0.75 ? math.sin(math.pi * pos / 0.75) : 0.0;
    return (amplitude * env * math.sin(2 * math.pi * freq * t)).round();
  });
}

/// 均匀噪声（模拟环境底噪 / 空调声）
List<int> _noise(double seconds, int amplitude, {int seed = 7}) {
  final n = (seconds * _rate).round();
  var x = seed;
  return List<int>.generate(n, (_) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    return ((x % (2 * amplitude + 1)) - amplitude);
  });
}

void main() {
  group('WAV 解析', () {
    test('读出采样率/声道/时长', () {
      final fmt = VoiceDetector.parseWavFormat(_wav(_speech(0.5, 8000)));
      expect(fmt, isNotNull);
      expect(fmt!.sampleRate, _rate);
      expect(fmt.channels, 1);
      expect(fmt.bitsPerSample, 16);
      expect(fmt.durationSec, closeTo(0.5, 0.01));
    });

    test('非 WAV 字节返回 null', () {
      final junk = Uint8List.fromList(List<int>.filled(200, 0x41));
      expect(VoiceDetector.parseWavFormat(junk), isNull);
    });

    test('8bit 不做判断（交给调用方直接识别）', () {
      final wav = _wav(_speech(0.5, 60), bitsPerSample: 8);
      expect(VoiceDetector.analyzeBytes(wav), isNull);
    });

    test('data 长度写成 0 的边录边写文件：用实际长度兜底', () {
      // record 插件在 Android 上是边录边写，某些实现会把 data 大小留成 0，
      // 这时必须按文件实际长度算，否则整个检测会被跳过
      final patched = Uint8List.fromList(_wav(_speech(1, 8000)));
      ByteData.sublistView(patched).setUint32(40, 0, Endian.little);

      final fmt = VoiceDetector.parseWavFormat(patched);
      expect(fmt, isNotNull);
      expect(fmt!.dataLength, greaterThan(0));
      expect(VoiceDetector.analyzeBytes(patched)!.hasSpeech, isTrue);
    });
  });

  group('人声检测', () {
    test('纯静音：判为没听到人声', () {
      final act = VoiceDetector.analyzeBytes(_wav(List<int>.filled(_rate, 0)));
      expect(act, isNotNull);
      expect(act!.hasSpeech, isFalse);
      expect(act.hint, contains('没听到人声'));
    });

    test('安静房间底噪：判为没听到人声', () {
      final act = VoiceDetector.analyzeBytes(_wav(_noise(2, 30)));
      expect(act!.hasSpeech, isFalse);
      expect(act.hint, contains('没听到人声'));
    });

    test('被系统增益放大的恒定噪声（能量不低但不是人声）：也要判掉', () {
      // 振幅 1500 峰值约 -27dB，绝对能量门槛过得去，
      // 靠"帧能量有没有起伏"这条相对判据拦住
      final act = VoiceDetector.analyzeBytes(_wav(_noise(2, 1500)));
      expect(act!.peakDbfs, greaterThan(VoiceActivity.minPeakDbfs));
      expect(act.voicedRatio, lessThan(VoiceActivity.minVoicedRatio));
      expect(act.hasSpeech, isFalse);
    });

    test('正常说话：不能误杀', () {
      final act = VoiceDetector.analyzeBytes(_wav(_speech(1.2, 8000)));
      expect(act!.hasSpeech, isTrue);
    });

    test('小声说话（峰值约 -35dB）：不能误杀', () {
      final act = VoiceDetector.analyzeBytes(_wav(_speech(1.2, 600)));
      expect(act!.peakDbfs, lessThan(-30));
      expect(act.hasSpeech, isTrue);
    });

    test('安静环境里说半句：不能误杀', () {
      final samples = <int>[
        ..._noise(0.6, 20),
        ..._speech(0.6, 6000),
      ];
      final act = VoiceDetector.analyzeBytes(_wav(samples));
      expect(act!.hasSpeech, isTrue);
    });

    test('按一下就松手（时长太短）：提示说完整', () {
      final act = VoiceDetector.analyzeBytes(_wav(_speech(0.1, 8000)));
      expect(act!.tooShort, isTrue);
      expect(act.hasSpeech, isFalse);
      expect(act.hint, contains('太短'));
    });
  });
}
