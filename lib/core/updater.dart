import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'native.dart';

/// 一次更新的候选信息。
class UpdateInfo {
  final String tag; // v1.0.5
  final String version; // 1.0.5
  final String notes;
  final String? apkUrl;
  final String? ipaUrl;
  final int apkSize;
  final int ipaSize;
  final String pageUrl;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.ipaUrl,
    required this.apkSize,
    required this.ipaSize,
    required this.pageUrl,
  });
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => '已取消';
}

class DownloadFailed implements Exception {
  final String message;
  const DownloadFailed(this.message);
  @override
  String toString() => message;
}

/// 下载句柄，用来让「取消」按钮能真的把正在流式写入的下载掐掉。
class DownloadTask {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 在线更新。
///
/// 更新源就是 GitHub Releases（仓库是公开的，不需要服务器）：
///   GET /repos/Corpse-zhao/DataVision/releases/latest → tag_name / body / assets
/// 拿 tag 和本地版本比，比本地新才提示。
///
/// 两端能力不一样，这里分得很清楚：
///   Android：能真更新 —— 下 APK（49 MB）→ 交给系统安装器覆盖安装。前提是新包用同一个
///            keystore 签名（CI 里固定了 datavision.jks），否则系统直接拒绝。
///   iOS：   系统不允许 App 装 App，只能把 IPA 链接甩给浏览器，用户自己用全能签重签。
class Updater {
  Updater._();
  static final Updater instance = Updater._();

  static const repo = 'Corpse-zhao/DataVision';
  static const apiUrl = 'https://api.github.com/repos/$repo/releases/latest';
  static const pageUrl = 'https://github.com/$repo/releases/latest';
  static const _ua = 'DataVision-Updater';

  /// 国内直连 release 资产经常断，按顺序试，第一个成了就停
  static const _cdnMirrors = <String>[
    'https://ghfast.top/', // 实测可用
    'https://ghproxy.net/',
  ];

  String _currentVersion = '';
  int _currentBuild = 0;

  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;

  /// 界面上显示的版本号，形如 v1.0.4 (5)
  String get displayVersion {
    if (_currentVersion.isEmpty) return '—';
    return _currentBuild > 0 ? 'v$_currentVersion ($_currentBuild)' : 'v$_currentVersion';
  }

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // 测试环境或平台通道没起来时，保持空串，退化成「不检查更新」
    }
  }

  /// 查最新版本；没有新版本或网络不通都返回 null（静默）。
  Future<UpdateInfo?> check({Duration timeout = const Duration(seconds: 12)}) async {
    if (_currentVersion.isEmpty) return null;
    final json = await _getJson(apiUrl, timeout);
    // 网络不通要能和「已经是最新版」区分开，所以这里抛，不返回 null
    if (json == null) throw const DownloadFailed('查不到版本信息，检查一下网络或稍后再试');

    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;
    final latest = normalizeVersion(tag);
    if (latest.isEmpty) return null;
    if (compareVersions(latest, _currentVersion) <= 0) return null;

    var apkUrl = '';
    var ipaUrl = '';
    var apkSize = 0;
    var ipaSize = 0;
    final assets = json['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] as String?)?.toLowerCase() ?? '';
        final url = (a['browser_download_url'] as String?) ?? '';
        final size = (a['size'] as num?)?.toInt() ?? 0;
        if (name.endsWith('.apk') && url.isNotEmpty) {
          apkUrl = url;
          apkSize = size;
        } else if (name.endsWith('.ipa') && url.isNotEmpty) {
          ipaUrl = url;
          ipaSize = size;
        }
      }
    }

    return UpdateInfo(
      tag: tag,
      version: latest,
      notes: (json['body'] as String?) ?? '',
      apkUrl: apkUrl.isEmpty ? null : apkUrl,
      ipaUrl: ipaUrl.isEmpty ? null : ipaUrl,
      apkSize: apkSize,
      ipaSize: ipaSize,
      pageUrl: (json['html_url'] as String?) ?? pageUrl,
    );
  }

  /// 带进度地下载 APK，直接落到原生给的 update 目录。
  Future<File> downloadApk(
    UpdateInfo info, {
    required DownloadTask task,
    void Function(int received, int total)? onProgress,
  }) async {
    final raw = info.apkUrl;
    if (raw == null) throw const DownloadFailed('这个版本没有 APK 资产');

    final dir = await Native.updateDir();
    if (dir == null) throw const DownloadFailed('拿不到下载目录');
    final target = File('$dir/datavision-${info.version}.apk');

    Object? lastError;
    for (final url in candidateUrls(raw)) {
      if (task.cancelled) throw const DownloadCancelled();
      try {
        return await _fetchToFile(url, target, task, onProgress);
      } catch (e) {
        lastError = e;
        if (task.cancelled || e is DownloadCancelled) throw const DownloadCancelled();
      }
    }
    throw DownloadFailed(lastError == null ? '下载失败' : '下载失败：$lastError');
  }

  /// 交给系统安装器
  Future<String> install(File apk) => Native.installApk(apk.path);

  /// 所有候选下载地址：原始地址在前，镜像在后
  static List<String> candidateUrls(String raw) {
    final out = <String>[raw];
    for (final m in _cdnMirrors) {
      out.add('$m$raw');
    }
    return out;
  }

  Future<File> _fetchToFile(
    String url,
    File target,
    DownloadTask task,
    void Function(int, int)? onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.followRedirects = true;
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        throw DownloadFailed('HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      await target.parent.create(recursive: true);
      if (target.existsSync()) target.deleteSync();
      sink = target.openWrite();

      var received = 0;
      var lastReport = 0;
      await for (final chunk in res) {
        if (task.cancelled) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (onProgress != null && (now - lastReport > 120 || received == total)) {
          lastReport = now;
          onProgress(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (total > 0 && received != total) {
        throw const DownloadFailed('包没下完整');
      }
      if (received == 0) throw const DownloadFailed('空文件');
      return target;
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _getJson(String url, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// "v1.0.5" / "1.0.5" / "release-1.0.5" 都归一成 "1.0.5"
String normalizeVersion(String tag) {
  final m = RegExp(r'\d+(?:\.\d+)*').firstMatch(tag);
  return m?.group(0) ?? '';
}

/// 按数字段逐位比：1 > 0，相等继续；缺的位按 0 算。
/// 返回 1 表示 a 更新，-1 表示 a 更旧，0 相同。
int compareVersions(String a, String b) {
  List<int> parts(String s) {
    final n = normalizeVersion(s);
    if (n.isEmpty) return const <int>[];
    return n.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  final x = parts(a);
  final y = parts(b);
  final len = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < len; i++) {
    final l = i < x.length ? x[i] : 0;
    final r = i < y.length ? y[i] : 0;
    if (l != r) return l > r ? 1 : -1;
  }
  return 0;
}

/// 把字节数写成人类可读，用于按钮上的「49 MB」
String humanSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
