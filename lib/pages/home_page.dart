import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
// 7.5.0 主入口未导出这两个类型，从包内公开子库导入
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../models/bill.dart';
import '../services/api_service.dart';
import '../services/app_events.dart';
import '../services/asr_model_controller.dart';
import '../services/database_service.dart';
import '../services/error_reporter.dart';
import '../services/haptics.dart';
import '../services/offline_asr_service.dart';
import '../services/privacy_controller.dart';
import '../services/voice_activity.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/bill_edit_sheet.dart';
import 'manual_entry_page.dart';

/// 记账首页
///
/// 信息层级：本月概览 → 一句话输入（主操作）→ 语音/手动两个次级入口
/// → 最近记账。麦克风从输入框的 suffixIcon 里拿出来做成独立按钮，
/// 因为"长按说话"是隐藏交互，藏在图标里没人会发现。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  final _textFocus = FocusNode();

  bool _isProcessing = false;

  // 本月概览
  double _monthExpense = 0;
  double _monthIncome = 0;
  List<Bill> _recentBills = [];

  // ── 语音 ─────────────────────────────────────────────
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _voiceText = '';

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _transcribing = false;
  String? _voiceFile;

  StreamSubscription<Amplitude>? _ampSub;
  double _level = 0;
  bool _ampReceived = false;

  // 长按判定：用 Listener 直接收原始触摸事件，不参与手势竞争
  Timer? _holdTimer;
  bool _pointerDown = false;
  bool _holdConfirmed = false;

  // 录音前的检查结果缓存，避免每次长按都走平台调用
  bool _micPermissionChecked = false;
  bool _micGranted = false;
  String? _tmpDir;

  final _model = AsrModelController.instance;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
    _loadOverview();
    AppEvents.instance.addListener(_onBillsChanged);
  }

  @override
  void dispose() {
    AppEvents.instance.removeListener(_onBillsChanged);
    _model.removeListener(_onModelChanged);
    _speech.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _holdTimer?.cancel();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  void _onBillsChanged() {
    if (mounted) _loadOverview();
  }

  Future<void> _loadOverview() async {
    try {
      final now = DateTime.now();
      final ym = DateFormat('yyyy-MM').format(now);
      final summary = await DatabaseService.instance.getMonthlySummary(ym);
      final recent = await DatabaseService.instance.getRecentBills(limit: 4);
      if (!mounted) return;
      setState(() {
        _monthExpense = summary['支出'] ?? 0;
        _monthIncome = summary['收入'] ?? 0;
        _recentBills = recent;
      });
    } catch (_) {
      // 首次使用数据库还没建好，忽略
    }
  }

  // ── 语音输入 ─────────────────────────────────────────

  Future<bool> _ensureSpeech() async {
    if (_speechReady) return true;
    bool available;
    try {
      available = await _speech.initialize(onError: _onSpeechError);
    } catch (_) {
      available = false;
    }
    if (mounted) setState(() => _speechReady = available);
    return available;
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    if (_listening) setState(() => _listening = false);
    if (error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout') {
      return;
    }
    showAppSnack(context, '语音识别出错：${error.errorMsg}', kind: SnackKind.error);
  }

  /// 按下麦克风：立即开录，不等长按判定
  ///
  /// 录音启动有 100~200ms 延迟，等 350ms 长按确认后再开录，
  /// 开头一两个字必然被吃掉。所以按下即录，判定为短按再丢弃。
  void _onMicPointerDown() {
    if (_isProcessing || _transcribing || _model.downloading || _recording) {
      return;
    }
    _pointerDown = true;
    _holdConfirmed = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_pointerDown) return;
      unawaited(Haptics.tap());
      if (mounted) setState(() => _holdConfirmed = true);
    });
    unawaited(_beginRecording());
  }

  void _onMicPointerUp() {
    _pointerDown = false;
    _holdTimer?.cancel();
    if (!_holdConfirmed) {
      _discardRecording();
      return;
    }
    _stopVoiceHold();
  }

  Future<void> _beginRecording() async {
    // 1. 麦克风权限（授权过就不再走平台查询）
    if (!_micPermissionChecked) {
      var perm = await Permission.microphone.status;
      if (perm.isDenied) perm = await Permission.microphone.request();
      _micPermissionChecked = true;
      _micGranted = perm.isGranted;
      if (!_micGranted) {
        if (perm.isPermanentlyDenied) openAppSettings();
        _pointerDown = false;
        if (mounted) {
          showAppSnack(context, '需要麦克风权限才能语音输入', kind: SnackKind.error);
        }
        return;
      }
    }
    if (!_micGranted) return;

    // 2. 模型是否就绪
    final ready = await _model.ensureChecked();
    if (!ready) {
      if (!mounted) return;
      _pointerDown = false;
      await _promptDownloadModel();
      return;
    }

    // 权限弹窗/下载对话框期间已经抬手 → 不录
    if (!_pointerDown) return;

    // 边录边加载模型：首次创建识别器要 1~2 秒，正好和说话时间重叠
    unawaited(OfflineAsrService.ensureLoaded().catchError((_) {}));

    try {
      final dirPath = _tmpDir ?? (await getTemporaryDirectory()).path;
      _tmpDir = dirPath;
      _voiceFile =
          '$dirPath/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _voiceFile!,
      );
      if (!_pointerDown) {
        await _discardRecording();
        return;
      }
      if (mounted) {
        setState(() {
          _recording = true;
          _voiceText = '';
        });
        _startLevelMeter();
      }
    } catch (e, st) {
      ErrorReporter.report('voice_record_start', e, st);
      if (mounted) {
        showAppSnack(context, '录音启动失败：$e', kind: SnackKind.error);
      }
    }
  }

  Future<void> _discardRecording() async {
    if (!_recording && _voiceFile == null) return;
    _stopLevelMeter();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    try {
      final f = _voiceFile == null ? null : File(_voiceFile!);
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
    _voiceFile = null;
  }

  void _startLevelMeter() {
    _ampSub?.cancel();
    _ampReceived = false;
    _level = 0;
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      if (!mounted) return;
      final norm = ((amp.current + 50) / 50).clamp(0.0, 1.0);
      _ampReceived = true;
      if ((norm - _level).abs() < 0.04) return;
      setState(() => _level = norm);
    }, onError: (_) {
      _ampReceived = false;
    });
  }

  void _stopLevelMeter() {
    _ampSub?.cancel();
    _ampSub = null;
    _ampReceived = false;
    _level = 0;
  }

  /// 松手 → 结束录音 → 人声检测 → 离线识别 → 回填输入框
  Future<void> _stopVoiceHold() async {
    if (!_recording) return;
    _stopLevelMeter();
    setState(() {
      _recording = false;
      _transcribing = true;
    });

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      ErrorReporter.report('voice_record_stop', e, st);
    }

    if (path == null || !File(path).existsSync()) {
      if (mounted) setState(() => _transcribing = false);
      return;
    }

    try {
      // 纯静音/环境噪声喂给 Paraformer 不会返回空串，而是"脑补"一段话，
      // 所以先做一次能量检测，没人声就直接拦掉、不浪费一次推理
      final activity = await VoiceDetector.analyzeFile(path);
      if (activity != null && !activity.hasSpeech) {
        if (mounted) {
          setState(() => _transcribing = false);
          showAppSnack(context, activity.hint);
        }
        return;
      }

      final text = await OfflineAsrService.transcribe(path);
      if (!mounted) return;
      setState(() => _transcribing = false);

      if (text.isEmpty) {
        showAppSnack(context, '没听清，长按麦克风再说一次');
        return;
      }

      // 只回填输入框，不直接弹账单：识别可能听错，先让用户核对
      _textController.text = text;
      _textController.selection = TextSelection.collapsed(offset: text.length);
      showAppSnack(context, '已转成文字，确认后点「AI 识别记账」',
          kind: SnackKind.success);
    } catch (e, st) {
      ErrorReporter.report('voice_transcribe', e, st);
      if (mounted) {
        setState(() => _transcribing = false);
        showAppSnack(context, '识别失败：$e', kind: SnackKind.error);
      }
    } finally {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// 模型未就绪时的引导
  Future<void> _promptDownloadModel() async {
    final model = _model.model;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要先下载语音模型'),
        content: Text(
          '离线识别要在手机上装一个中文语音模型'
          '（${model.label}，约 ${model.totalMb} MB）。\n\n'
          '只需下载一次，之后完全离线：不联网、不上传录音，'
          '在外面没 WiFi 也能用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'system'),
            child: const Text('用系统识别'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'download'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(88, 42)),
            child: const Text('下载'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'download') {
      final ok = await _model.download();
      if (!mounted) return;
      showAppSnack(
        context,
        ok ? '模型已就绪，长按麦克风试试' : '下载未完成，请检查网络后重试',
        kind: ok ? SnackKind.success : SnackKind.error,
      );
    } else if (choice == 'system') {
      await _toggleSystemVoice();
    }
  }

  /// 系统识别（仅在模型未下载时作为兜底）
  Future<void> _toggleSystemVoice() async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    if (_isProcessing) return;

    var perm = await Permission.microphone.status;
    if (perm.isDenied) perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      if (perm.isPermanentlyDenied) openAppSettings();
      if (mounted) {
        showAppSnack(context, '需要麦克风权限才能语音输入', kind: SnackKind.error);
      }
      return;
    }

    if (!await _ensureSpeech()) {
      if (mounted) {
        showAppSnack(context, '系统语音识别不可用：华为设备可先安装"讯飞输入法"',
            kind: SnackKind.error);
      }
      return;
    }

    _textController.clear();
    _voiceText = '';
    setState(() => _listening = true);
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 2),
          localeId: 'zh_CN',
          listenMode: ListenMode.dictation,
        ),
      );
      if (mounted && !_speech.isListening && _listening) {
        setState(() => _listening = false);
        showAppSnack(context, '语音识别不可用：可尝试安装讯飞输入法后重试',
            kind: SnackKind.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        showAppSnack(context, '语音识别不可用：可尝试安装讯飞输入法后重试',
            kind: SnackKind.error);
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _voiceText = result.recognizedWords);
    if (!result.finalResult) return;

    setState(() => _listening = false);
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    _textController.text = text;
    _sendToAI(text);
  }

  // ── AI 解析 ───────────────────────────────────────────

  Future<void> _sendToAI(String text) async {
    final input = text.trim();
    if (input.isEmpty) {
      showAppSnack(context, '先说一句话，比如「中午吃饭花了25」');
      _textFocus.requestFocus();
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final bill = await ApiService.extractBill(input);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      showAppSnack(
        context,
        ApiService.lastUsedRemote ? '已用云端 AI 解析' : '已用本地引擎解析（离线）',
        kind: SnackKind.success,
      );
      _showConfirmSheet(bill, sourceText: input);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      showAppSnack(context, '解析出错：$e', kind: SnackKind.error);
    }
  }

  void _showConfirmSheet(Bill bill, {String? sourceText}) {
    showBillEditSheet(
      context: context,
      bill: bill,
      title: '确认记账',
      saveLabel: '确认保存',
      sourceText: sourceText,
      onSave: (edited) async {
        await DatabaseService.instance.insertBill(edited);
        _textController.clear();
        AppEvents.instance.billsChanged();
        if (mounted) {
          showAppSnack(context, '已记一笔', kind: SnackKind.success);
        }
      },
    );
  }

  Future<void> _openManualEntry() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ManualEntryPage()),
    );
    if (saved == true) {
      AppEvents.instance.billsChanged();
      if (mounted) showAppSnack(context, '已记一笔', kind: SnackKind.success);
    }
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppGap.lg),
            child: Center(
              child: Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now()),
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppGap.lg, AppGap.sm, AppGap.lg, AppGap.xxl),
        children: [
          _buildOverviewCard(),
          const SizedBox(height: AppGap.lg),
          _buildInputCard(),
          const SizedBox(height: AppGap.md),
          _buildSecondaryActions(),
          _buildVoiceStatus(),
          const SizedBox(height: AppGap.xxl),
          SectionTitle(
            title: '最近记账',
            actionLabel: _recentBills.isEmpty ? null : '全部',
            onAction: () => AppEvents.instance.switchTab(1),
          ),
          _buildRecentCard(),
        ],
      ),
    );
  }

  /// 本月概览：让首页一眼看到"这个月花了多少"
  ///
  /// 金额默认遮起来（旁边有人瞄一眼就全看见了），点眼睛才显示；
  /// 整张卡可点，进入账单页看明细。
  Widget _buildOverviewCard() {
    return AnimatedBuilder(
      animation: PrivacyController.instance,
      builder: (context, _) {
        final visible = PrivacyController.instance.amountVisible;
        final monthLabel = DateFormat('M月').format(DateTime.now());
        final balance = _monthIncome - _monthExpense;

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A55E0), Color(0xFF6C86FF)],
                ),
              ),
              child: InkWell(
                onTap: () => AppEvents.instance.switchTab(1),
                child: Stack(
                  children: [
                    // 右上角一枚很淡的装饰圆，避免大色块显得死板
                    Positioned(
                      right: -30,
                      top: -40,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppGap.xl, AppGap.lg, AppGap.lg, AppGap.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$monthLabel支出',
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xCCFFFFFF)),
                              ),
                              const Spacer(),
                              _buildEyeButton(visible),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            moneyDisplay(_monthExpense, visible: visible),
                            style: moneyStyle(
                                size: 34,
                                color: Colors.white,
                                letterSpacing: -0.8),
                          ),
                          const SizedBox(height: AppGap.lg),
                          Row(
                            children: [
                              _miniStat('收入', _monthIncome, visible),
                              const SizedBox(width: AppGap.xl),
                              _miniStat('结余', balance, visible),
                            ],
                          ),
                          const SizedBox(height: AppGap.md),
                          // 明确告诉用户这张卡可以点
                          Row(
                            children: [
                              Text(
                                '查看账单明细',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.75)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEyeButton(bool visible) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => PrivacyController.instance.toggle(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          size: 17,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _miniStat(String label, double value, bool visible) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xB3FFFFFF))),
        const SizedBox(width: 6),
        Text(
          moneyDisplay(value, visible: visible),
          style: moneyStyle(
              size: 14, color: Colors.white, weight: FontWeight.w600),
        ),
      ],
    );
  }

  /// 一句话输入卡（主操作区）
  Widget _buildInputCard() {
    final palette = context.palette;

    return AppCard(
      padding: const EdgeInsets.all(AppGap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 15, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: AppGap.sm),
              Text(
                '一句话记账',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppGap.md),
          TextField(
            controller: _textController,
            focusNode: _textFocus,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: _sendToAI,
            style: const TextStyle(fontSize: 16, height: 1.45),
            decoration: InputDecoration(
              hintText: '例如：今天中午吃黄焖鸡花了25元',
              hintStyle: TextStyle(fontSize: 15, color: palette.textTertiary),
              suffixIcon: _textController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _textController.clear();
                        setState(() {});
                      },
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: palette.textTertiary),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppGap.md),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 19),
              label: Text(_isProcessing ? '解析中…' : 'AI 识别记账'),
              onPressed:
                  _isProcessing ? null : () => _sendToAI(_textController.text),
            ),
          ),
        ],
      ),
    );
  }

  /// 两个次级入口：长按说话 / 手动填写
  Widget _buildSecondaryActions() {
    final busy = _isProcessing || _transcribing || _model.downloading;

    return Row(
      children: [
        Expanded(child: _buildMicButton(busy)),
        const SizedBox(width: AppGap.md),
        Expanded(child: _buildManualButton(busy)),
      ],
    );
  }

  /// 麦克风：明确的按钮形态 + 文字说明，按住变红提示"松手结束"
  Widget _buildMicButton(bool busy) {
    final palette = context.palette;
    final active = _recording && _holdConfirmed;
    final accent = palette.expense;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: busy ? null : (_) => _onMicPointerDown(),
      onPointerUp: busy ? null : (_) => _onMicPointerUp(),
      onPointerCancel: busy ? null : (_) => _onMicPointerUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? palette.expenseSoft
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: active ? accent : palette.hairline,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                  size: 19,
                  color: active ? accent : palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  active ? '松手结束' : '长按说话',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: active ? accent : palette.textSecondary,
                  ),
                ),
              ],
            ),
            if (active && _ampReceived) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _level,
                    minHeight: 3,
                    backgroundColor: accent.withValues(alpha: 0.18),
                    color: accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualButton(bool busy) {
    final palette = context.palette;
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        icon: Icon(Icons.edit_note_rounded,
            size: 20, color: palette.textSecondary),
        label: Text(
          '手动填写',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        onPressed: busy ? null : _openManualEntry,
        style: OutlinedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          side: BorderSide(color: palette.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }

  /// 语音/下载状态条（录音中的反馈在麦克风按钮上）
  Widget _buildVoiceStatus() {
    final palette = context.palette;

    String? text;
    double? progress;
    if (_model.downloading) {
      text = '正在下载语音模型 ${(_model.progress * 100).toStringAsFixed(0)}%';
      progress = _model.progress;
    } else if (_transcribing) {
      text = '正在识别…';
    } else if (_listening) {
      text = _voiceText.isEmpty ? '正在聆听…说完停顿一下' : _voiceText;
    }

    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppGap.md),
      child: Container(
        padding: const EdgeInsets.all(AppGap.md),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppGap.sm),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: palette.textSecondary),
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: AppGap.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: progress),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard() {
    if (_recentBills.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.zero,
        child: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: '还没有账单',
          subtitle: '在上面说一句「中午吃饭花了25」，\n剩下的交给 AI。',
        ),
      );
    }

    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _recentBills.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: palette.hairline,
              ),
            BillTile(bill: _recentBills[i]),
          ],
        ],
      ),
    );
  }
}
