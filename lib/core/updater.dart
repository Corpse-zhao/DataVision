import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const pageUrl = 'https://github.com/$repo/releases';

  /// 用列表接口而不是 /releases/latest：latest 不返回被标成 prerelease 的版本，
  /// 而 CI 建 release 时确实标过 prerelease，结果接口直接 404，前端看着就像"网络不通"。
  /// 列表接口一律返回全部，自己在里面挑版本号最大的那个，反而更稳。
  static const apiListUrl = 'https://api.github.com/repos/$repo/releases?per_page=10';

  /// API 走不通时（运营商封 api.github.com）退回静态文件，多线路并发取
  static const staticVersionUrls = <String>[
    'https://cdn.jsdelivr.net/gh/$repo@main/version.json',
    'https://fastly.jsdelivr.net/gh/$repo@main/version.json',
    'https://gcore.jsdelivr.net/gh/$repo@main/version.json',
    'https://raw.githubusercontent.com/$repo/main/version.json',
    'https://ghfast.top/https://raw.githubusercontent.com/$repo/main/version.json',
  ];

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

  /// 界面上只显示版本号，形如 v1.0.6。
  ///
  /// 构建号不显示：之前写成 "v1.0.6 (7)"，括号里的 7 太容易被读成版本号的一截
  /// （"是不是 1.0.7 了？"）。构建号只用来给系统比新旧，留在内部就够了。
  String get displayVersion => _currentVersion.isEmpty ? '—' : 'v$_currentVersion';

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // 测试环境或平台通道没起来时，保持空串，退化成「不检查更新」
    }
  }

  /// 查最新版本。返回 null = 已经是最新的；连不上则抛 [DownloadFailed]。
  Future<UpdateInfo?> check({Duration timeout = const Duration(seconds: 7)}) async {
    if (_currentVersion.isEmpty) return null;

    var info = await _fromApi(timeout);
    info ??= await _fromStatic(timeout);
    if (info == null) {
      throw const DownloadFailed('连不上更新服务器，可以点「打开下载页」手动看');
    }
    if (compareVersions(info.version, _currentVersion) <= 0) return null;
    return info;
  }

  /// 线路一：GitHub API 的 release 列表，挑版本号最大的那条（draft 不算）。
  Future<UpdateInfo?> _fromApi(Duration timeout) async {
    final raw = await _getJson(apiListUrl, timeout);
    if (raw is! List) return null;
    return pickNewestRelease(raw);
  }

  /// 线路二：仓库里的 version.json，走 jsDelivr / raw 等多条 CDN。
  Future<UpdateInfo?> _fromStatic(Duration timeout) async {
    final map = await _firstJson(staticVersionUrls, timeout);
    if (map == null) return null;
    return infoFromStatic(map);
  }

  /// 从 release 列表里挑版本最高的（忽略 draft，但**不忽略 prerelease**）——
  /// 就是这条规则踩过坑，所以留个公开方法方便测试。
  static UpdateInfo? pickNewestRelease(List<dynamic> list) {
    UpdateInfo? best;
    for (final item in list) {
      if (item is! Map) continue;
      if (item['draft'] == true) continue;
      final tag = (item['tag_name'] as String?)?.trim() ?? '';
      final version = normalizeVersion(tag);
      if (tag.isEmpty || version.isEmpty) continue;
      if (best != null && compareVersions(version, best.version) <= 0) continue;
      best = infoFromRelease(item, tag, version);
    }
    return best;
  }

  /// 把一个 release 的 JSON 折成 UpdateInfo；资产地址缺失时按命名规则拼。
  static UpdateInfo infoFromRelease(Map<dynamic, dynamic> json, String tag, String version) {
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
      version: version,
      notes: (json['body'] as String?) ?? '',
      apkUrl: apkUrl.isEmpty ? _assetUrl(tag, 'apk') : apkUrl,
      ipaUrl: ipaUrl.isEmpty ? _assetUrl(tag, 'ipa') : ipaUrl,
      apkSize: apkSize,
      ipaSize: ipaSize,
      pageUrl: (json['html_url'] as String?) ?? pageUrl,
    );
  }

  /// version.json 的结构：{"version": "1.0.6", "tag": "v1.0.6", "notes": "..."}
  static UpdateInfo? infoFromStatic(Map<dynamic, dynamic> json) {
    final version = normalizeVersion((json['version'] as String?) ?? (json['tag'] as String?) ?? '');
    if (version.isEmpty) return null;
    final tag = ((json['tag'] as String?)?.trim().isNotEmpty ?? false)
        ? (json['tag'] as String).trim()
        : 'v$version';
    return UpdateInfo(
      tag: tag,
      version: version,
      notes: (json['notes'] as String?) ?? '',
      apkUrl: _assetUrl(tag, 'apk'),
      ipaUrl: _assetUrl(tag, 'ipa'),
      apkSize: (json['apkSize'] as num?)?.toInt() ?? 0,
      ipaSize: (json['ipaSize'] as num?)?.toInt() ?? 0,
      pageUrl: (json['page'] as String?) ?? pageUrl,
    );
  }

  static String _assetUrl(String tag, String ext) =>
      'https://github.com/$repo/releases/download/$tag/DataVision-$tag.$ext';

  /// 打开下载页（iOS 没有 App 内安装，这个是给用户的出口）
  Future<bool> openDownloadPage() async {
    try {
      return await launchUrl(Uri.parse(pageUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// 多条线路同时打，谁先给出有效 JSON 就用谁；全挂了才返回 null。
  Future<Map<String, dynamic>?> _firstJson(List<String> urls, Duration timeout) async {
    final completer = Completer<Map<String, dynamic>?>();
    var pending = urls.length;
    for (final url in urls) {
      _getJson(url, timeout).then((value) {
        if (value is Map<String, dynamic> && !completer.isCompleted) {
          completer.complete(value);
        }
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }
    return completer.future;
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
    // idleTimeout 是给"连上了但一直不来数据"兜底的：卡住 30 秒直接报错，
    // 不然弹窗会永远停在某个百分比上，取消按钮也掐不断（没有 chunk 就没有检查点）
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
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

  Future<dynamic> _getJson(String url, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      return jsonDecode(body);
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
