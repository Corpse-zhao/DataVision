import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/updater.dart';
import 'theme.dart';

/// 弹更新提示。返回值：
///   'installing' —— Android 已把安装包交给系统
///   'opened'     —— iOS 已把下载链接丢给浏览器
///   null         —— 用户点了稍后 / 取消
Future<String?> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(info: info),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _task = DownloadTask();
  double? _fraction;
  int _received = 0;
  int _total = 0;
  String? _error;
  String? _hint;
  bool _busy = false;

  bool get _android => Platform.isAndroid;
  String get _ver => widget.info.version;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_circle_up_rounded, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发现新版本 v$_ver',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('当前 ${Updater.instance.displayVersion}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (info.notes.trim().isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.notes.trim(),
                    style: const TextStyle(fontSize: 12, height: 1.55, color: AppColors.ink),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('（这一版没写更新说明）',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
              ),
            const SizedBox(height: 12),
            if (_busy) _progressBlock() else _actionBlock(),
            if (_hint != null) ...[
              const SizedBox(height: 10),
              _note(_hint!, AppColors.warn),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _note(_error!, AppColors.bad),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? () {
                  _task.cancel();
                }
              : () => Navigator.of(context).pop(),
          child: Text(_busy ? '取消下载' : '稍后'),
        ),
        if (!_busy)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: _android ? _downloadAndInstall : _openForIos,
            child: Text(_android
                ? '立即更新${info.apkSize > 0 ? '（${humanSize(info.apkSize)}）' : ''}'
                : '下载 IPA${info.ipaSize > 0 ? '（${humanSize(info.ipaSize)}）' : ''}'),
          ),
      ],
    );
  }

  Widget _actionBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(
          _android
              ? '下载完成后会直接弹出系统安装界面，覆盖安装即可，已记住的设备和设置不会丢。'
              : 'iOS 系统不允许 App 自己装 App。点下面按钮把 IPA 下到「文件」里，再用全能签重新签名安装'
                  '——Bundle ID 保持和上次一致，覆盖安装后数据在。',
          AppColors.inkSoft,
        ),
        if (!_android) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
              onPressed: () async {
                await _launch(widget.info.pageUrl);
                if (mounted) Navigator.of(context).pop('opened');
              },
              child: const Text('打开版本页（看说明 / 手动选包）', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _progressBlock() {
    final f = _fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 7,
            backgroundColor: AppColors.line,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              f == null ? '正在下载…' : '正在下载 ${(_fraction! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
            const Spacer(),
            Text(
              _total > 0
                  ? '${humanSize(_received)} / ${humanSize(_total)}'
                  : humanSize(_received),
              style: AppTheme.mono.copyWith(fontSize: 11.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ],
    );
  }

  Widget _note(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 13, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11.5, height: 1.5, color: color)),
        ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
      _fraction = 0;
      _received = 0;
      _total = widget.info.apkSize;
    });

    try {
      final apk = await Updater.instance.downloadApk(
        widget.info,
        task: _task,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) {
              _total = total;
              _fraction = received / total;
            } else {
              _fraction = null;
            }
          });
        },
      );
      if (!mounted) return;

      final result = await Updater.instance.install(apk);
      if (!mounted) return;

      switch (result) {
        case 'ok':
          Navigator.of(context).pop('installing');
          break;
        case 'need_permission':
          setState(() {
            _busy = false;
            _hint = '已打开「安装未知应用」设置页。允许后回到这里再点一次「立即更新」，包已经下好，不会重下。';
          });
          break;
        default:
          setState(() {
            _busy = false;
            _error = '安装没起来：$result';
          });
      }
    } on DownloadCancelled {
      if (mounted) {
        setState(() {
          _busy = false;
          _fraction = null;
          _hint = '已取消下载';
        });
      }
    } on DownloadFailed catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _fraction = null;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _fraction = null;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _openForIos() async {
    final url = widget.info.ipaUrl ?? widget.info.pageUrl;
    final ok = await _launch(url);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop('opened');
    } else {
      setState(() => _error = '打不开浏览器，手动复制这个地址：$url');
    }
  }

  Future<bool> _launch(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
