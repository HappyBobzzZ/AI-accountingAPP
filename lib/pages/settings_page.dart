import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/asr_model_controller.dart';
import '../services/data_ops.dart';
import '../services/privacy_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// 设置页 —— 以前散落在首页 AppBar 的裸图标入口全部收在这里，
/// 每一项都写清楚"这是干什么的"。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _model = AsrModelController.instance;
  final _privacy = PrivacyController.instance;

  bool _serverChecked = false;
  bool _serverAvailable = false;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
    _privacy.addListener(_onModelChanged);
    _model.ensureChecked();
    _checkServer();
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _privacy.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkServer() async {
    final ok = await ApiService.checkHealth();
    if (!mounted) return;
    setState(() {
      _serverAvailable = ok;
      _serverChecked = true;
    });
  }

  Future<void> _downloadModel() async {
    final ok = await _model.download();
    if (!mounted) return;
    showAppSnack(
      context,
      ok ? '语音模型已就绪，长按首页麦克风试试' : '下载未完成，请检查网络后重试',
      kind: ok ? SnackKind.success : SnackKind.error,
    );
  }

  Future<void> _deleteModel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除语音模型'),
        content: Text(
          '删除后离线语音识别不可用，需要重新下载 ${_model.model.totalMb} MB。\n'
          '已记的账单不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: context.palette.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _model.remove();
    if (mounted) showAppSnack(context, '已删除，释放了 ${_model.model.totalMb} MB');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppGap.lg, AppGap.sm, AppGap.lg, AppGap.xxl),
        children: [
          _group('数据', [
            _Row(
              icon: Icons.cloud_download_rounded,
              title: '从电脑导入账单',
              subtitle: '把电脑上的历史账单同步进来，重复的会自动跳过',
              onTap: () => importBillsFlow(context),
            ),
            _divider(),
            _Row(
              icon: Icons.ios_share_rounded,
              title: '导出账单备份',
              subtitle: '导出成 CSV，可用 Excel / WPS 打开',
              onTap: () => exportBillsFlow(context),
            ),
          ]),

          _group('语音识别', [_buildModelRow()]),

          _group('隐私', [_buildPrivacyRow()]),

          _group('解析引擎', [_buildEngineRow()]),

          _group('关于', [
            _Row(
              icon: Icons.info_outline_rounded,
              title: '版本',
              subtitle: '1.4.1（2009）',
            ),
            _divider(),
            _Row(
              icon: Icons.lock_outline_rounded,
              title: '数据只存在本机',
              subtitle: '账单保存在手机本地数据库，不上传任何服务器',
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildModelRow() {
    final palette = context.palette;
    final model = _model.model;

    Widget trailing;
    if (_model.downloading) {
      trailing = Text(
        '${(_model.progress * 100).toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      );
    } else if (!_model.checked) {
      trailing = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_model.ready) {
      trailing = TextButton(
        onPressed: _deleteModel,
        child: Text('删除',
            style: TextStyle(color: palette.textSecondary, fontSize: 13)),
      );
    } else {
      trailing = TextButton(
        onPressed: _downloadModel,
        child: const Text('下载', style: TextStyle(fontSize: 13)),
      );
    }

    final subtitle = _model.downloading
        ? '正在下载 ${model.label}…'
        : _model.ready
            ? '${model.label} · ${model.totalMb} MB · 已就绪，可离线识别'
            : '${model.label} · 约 ${model.totalMb} MB · 未下载';

    return _Row(
      icon: Icons.record_voice_over_rounded,
      title: '离线语音模型',
      subtitle: subtitle,
      trailing: trailing,
      onTap: _model.downloading
          ? null
          : (_model.ready ? null : _downloadModel),
      progress: _model.downloading ? _model.progress : null,
    );
  }

  Widget _buildPrivacyRow() {
    final visible = _privacy.amountVisible;

    return _Row(
      icon: visible
          ? Icons.visibility_rounded
          : Icons.visibility_off_rounded,
      title: '显示金额',
      subtitle: visible
          ? '首页、账单、统计的汇总金额直接显示'
          : '汇总金额显示为 ¥ ••••，避免旁人一眼看到；点首页卡片上的眼睛可临时显示',
      trailing: Switch.adaptive(
        value: visible,
        onChanged: (v) => _privacy.setVisible(v),
      ),
      onTap: () => _privacy.setVisible(!visible),
    );
  }

  Widget _buildEngineRow() {
    final palette = context.palette;
    final label = !_serverChecked
        ? '正在检测…'
        : _serverAvailable
            ? '已连接电脑，优先用云端 AI 解析'
            : '未连接电脑，自动使用本地引擎（完全离线）';

    return _Row(
      icon: _serverAvailable
          ? Icons.cloud_done_rounded
          : Icons.phone_iphone_rounded,
      title: '当前解析引擎',
      subtitle: label,
      trailing: IconButton(
        onPressed: _checkServer,
        icon: Icon(Icons.refresh_rounded, size: 19,
            color: palette.textSecondary),
        style: IconButton.styleFrom(
          backgroundColor: palette.surfaceAlt,
          minimumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, AppGap.xl, 4, AppGap.sm),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: context.palette.textTertiary,
            ),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _divider() => Divider(
        height: 1,
        thickness: 1,
        indent: 60,
        color: context.palette.hairline,
      );
}

/// 设置项行：图标 + 标题 + 说明 + 右侧控件
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double? progress;

  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.lg, vertical: AppGap.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.brandSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon,
                size: 19, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: AppGap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: palette.textTertiary,
                    ),
                  ),
                ],
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
          if (trailing != null) ...[
            const SizedBox(width: AppGap.sm),
            trailing!,
          ],
        ],
      ),
    );

    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
