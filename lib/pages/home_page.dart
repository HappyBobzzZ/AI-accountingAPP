import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
// 7.5.0 主入口未导出这两个类型，从包内公开子库导入
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/bill.dart';
import '../services/api_service.dart';
import '../services/bill_import.dart';
import '../services/database_service.dart';
import '../services/error_reporter.dart';
import '../widgets/bill_edit_sheet.dart';
import 'bill_list_page.dart';
import 'manual_entry_page.dart';

/// 文字输入主页
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  final _textFocus = FocusNode();
  bool _isProcessing = false;
  bool _serverAvailable = false;
  bool _serverChecked = false;
  List<Bill> _recentBills = [];

  // ── 语音输入（系统识别引擎） ─────────────────────────
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false; // 系统语音识别是否可用（华为上需实测）
  bool _listening = false;
  String _voiceText = '';

  @override
  void initState() {
    super.initState();
    _loadRecentBills();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final ok = await ApiService.checkHealth();
    if (mounted) setState(() { _serverAvailable = ok; _serverChecked = true; });
  }

  // ── 语音输入 ─────────────────────────────────────────

  /// 初始化系统语音识别；华为无谷歌服务，能否用取决于系统/输入法提供的识别服务
  Future<bool> _ensureSpeech() async {
    if (_speechReady) return true;
    bool available = false;
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
    // 没听到内容或超时：静默结束
    if (error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout') {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('语音识别出错: ${error.errorMsg}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 点麦克风开始/停止听写；识别完成后自动走 AI 识别流程
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop(); // stop 会触发 finalResult
      return;
    }
    if (_isProcessing) return;

    // 1. 麦克风权限（点按才请求，不在启动时打扰）
    var perm = await Permission.microphone.status;
    if (perm.isDenied) perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      if (perm.isPermanentlyDenied) openAppSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要麦克风权限才能语音输入，请在设置中允许'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 2. 初始化系统识别（华为上取决于是否装了带识别服务的输入法）
    if (!await _ensureSpeech()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('系统语音识别不可用：请安装"讯飞输入法"后重试（它自带系统识别服务）'),
            duration: Duration(seconds: 4),
          ),
        );
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
          pauseFor: const Duration(seconds: 2), // 停顿 2 秒自动结束
          localeId: 'zh_CN',
          listenMode: ListenMode.dictation,
        ),
      );
      // 识别服务未真正启动（无异常但未在听）
      if (mounted && !_speech.isListening && _listening) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('语音识别不可用：华为设备可尝试安装讯飞输入法（自带系统识别服务）后重试'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('语音识别不可用：华为设备可尝试安装讯飞输入法（自带系统识别服务）后重试'),
            duration: Duration(seconds: 3),
          ),
        );
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
    // 识别完成 → 填入输入框并自动识别记账（确认弹窗里可改）
    _textController.text = text;
    _sendToAI(text);
  }

  @override
  void dispose() {
    _speech.cancel(); // 页面销毁时结束识别会话
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRecentBills() async {
    try {
      final bills = await DatabaseService.instance.getRecentBills();
      if (mounted) setState(() => _recentBills = bills);
    } on Exception {
      // 首次使用，数据库未初始化
    }
  }

  Future<void> _importBills() async {
    // 需要连接 PC 后端（WiFi 环境）
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final bills = await ApiService.fetchImportBills();
      if (!mounted) return;

      if (bills == null || bills.isEmpty) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获取到账单数据（需连接 WiFi 后端）')),
        );
        return;
      }

      // 增量导入：按内容指纹逐条去重，库里已有的跳过、只插入新账单，
      // 可反复导入而不产生重复
      final existing = await DatabaseService.instance.getExistingFingerprints();
      if (!mounted) return;

      final plan = planImport(bills, existing);

      if (plan.isEmpty) {
        setState(() => _isProcessing = false);
        _loadRecentBills();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('这 ${bills.length} 条账单已全部存在，无需重复导入'),
          ),
        );
        return;
      }

      final count = await DatabaseService.instance.bulkInsertBills(plan.fresh);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _loadRecentBills();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            plan.duplicated > 0
                ? '✅ 新增 $count 条，跳过 ${plan.duplicated} 条重复'
                : '✅ 成功导入 $count 条历史账单',
          ),
        ),
      );
    } catch (e, st) {
      if (mounted) {
        setState(() => _isProcessing = false);
        // 上报到电脑端（/api/log），排查真机错误
        ErrorReporter.report('import', e, st);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败，错误已上报电脑')),
        );
        // 弹出完整错误详情，方便截图/复制
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('导入失败'),
            content: SingleChildScrollView(
              child: SelectableText(e.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ── AI 分析 ────────────────────────────────────────────

  Future<void> _sendToAI(String text) async {
    if (text.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final bill = await ApiService.extractBill(text);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _serverAvailable = ApiService.lastUsedRemote;
      // 提示当前使用的解析模式
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.lastUsedRemote ? '✅ AI 云端解析完成' : '📱 本地引擎解析完成',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 240,
        ),
      );
      _showConfirmSheet(bill);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析出错: $e')),
        );
      }
    }
  }

  // ── 确认/手动 ─────────────────────────────────────────

  void _showConfirmSheet(Bill bill) {
    showBillEditSheet(
      context: context,
      bill: bill,
      title: '确认记账',
      saveLabel: '确认保存',
      onSave: (editedBill) async {
        await DatabaseService.instance.insertBill(editedBill);
        _textController.clear();
        _loadRecentBills();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ 记账成功！'), duration: Duration(seconds: 1)),
          );
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
      _loadRecentBills();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ 记账成功！'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导入历史账单',
            onPressed: _importBills,
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: '账单列表',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BillListPage()),
              ).then((_) => _loadRecentBills());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 引擎状态指示条 ──────────────────────────
          if (_serverChecked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: _serverAvailable
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _serverAvailable ? Icons.cloud_done : Icons.phone_android,
                    size: 14,
                    color: _serverAvailable
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _serverAvailable ? 'WiFi AI 引擎 · 云端解析' : '本地引擎 · 离线工作',
                    style: TextStyle(
                      fontSize: 12,
                      color: _serverAvailable
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _checkServer,
                    child: Icon(Icons.refresh, size: 14,
                        color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          if (_recentBills.isNotEmpty) _buildRecentBills(),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Icon(Icons.auto_awesome,
                        size: 48, color: Colors.blue.shade300),
                    const SizedBox(height: 12),
                    Text('输入一句话，AI 自动记账',
                        style:
                            TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                    const SizedBox(height: 24),

                    // 输入框
                    TextField(
                      controller: _textController,
                      focusNode: _textFocus,
                      maxLines: 2,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (text) => _sendToAI(text),
                      decoration: InputDecoration(
                        hintText: '例如：今天中午吃黄焖鸡花了25元',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: Colors.blue.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: Colors.blue.shade400, width: 2),
                        ),
                        prefixIcon: const Icon(Icons.edit_note),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 麦克风：点按后按需请求权限并初始化识别
                            IconButton(
                              icon: Icon(
                                  _listening ? Icons.stop : Icons.mic,
                                  size: 22),
                              color: _listening
                                  ? Colors.red
                                  : Colors.grey.shade600,
                              tooltip: _listening ? '停止' : '语音输入',
                              onPressed: _isProcessing ? null : _toggleVoice,
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _textController.clear();
                                // 使用 postFrameCallback 避免构建期间 setState
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) setState(() {});
                                });
                              },
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                    // 聆听状态条（实时显示识别文字）
                    if (_listening) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic, size: 16, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _voiceText.isEmpty
                                    ? '正在聆听…说完停顿一下，或再点麦克风结束'
                                    : _voiceText,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.red.shade700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // AI 识别按钮
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                            _isProcessing ? 'AI 分析中…' : 'AI 识别记账',
                            style: const TextStyle(fontSize: 16)),
                        onPressed: _isProcessing
                            ? null
                            : () => _sendToAI(_textController.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 手动记账按钮 — 直接填写表单，无需 AI 解析
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit_note),
                        label: const Text('手动记账',
                            style: TextStyle(fontSize: 16)),
                        onPressed: _isProcessing ? null : _openManualEntry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentBills() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('最近记账',
              style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recentBills.length,
              separatorBuilder: (ctx2, i2) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final b = _recentBills[i];
                return Chip(
                  avatar: Text(BillCategory.iconFor(b.category)),
                  label: Text(
                    '${b.isExpense ? "-" : "+"}¥${b.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: b.isExpense ? Colors.red : Colors.green,
                    ),
                  ),
                  backgroundColor: Colors.white,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
