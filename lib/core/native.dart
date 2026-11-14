import 'dart:io';

import 'package:flutter/services.dart';

/// 原生能力的薄封装。
///
/// 只有 Android 侧实现了安装 APK 的通道（见 MainActivity.kt）；
/// iOS 上这些方法会抛 MissingPluginException，这里统一吞掉并返回兜底值，
/// 所以上层调用方不需要自己判平台。
class Native {
  static const _ch = MethodChannel('datavision/native');

  /// 下载目录（Android 的 App 专属外部目录）。iOS 返回 null。
  static Future<String?> updateDir() async {
    if (!_isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('updateDir');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 系统是否已允许本应用安装未知来源的包。
  static Future<bool> canInstall() async {
    if (!_isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('canInstall') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 交给系统安装器。返回值：
  ///   ok              —— 系统安装界面已拉起
  ///   need_permission —— 已跳到「安装未知应用」设置页，用户授权后再调一次
  ///   missing_file    —— 文件不在或为 0 字节
  ///   unsupported     —— 非 Android
  ///   error:xxx       —— 其它异常
  static Future<String> installApk(String path) async {
    if (!_isAndroid) return 'unsupported';
    try {
      return await _ch.invokeMethod<String>('installApk', {'path': path}) ?? 'error:null';
    } on MissingPluginException {
      return 'unsupported';
    } on PlatformException catch (e) {
      return 'error:${e.message}';
    }
  }

  /// 用系统浏览器打开链接（Android 走通道，iOS 走 url_launcher）。
  static Future<bool> openUrl(String url) async {
    if (!_isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

bool get _isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}
