import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地记忆：记住连过的设备、跑通的信道、以及几个可调参数。
///
/// 「第一次手动连，以后搜到就自动连」全靠这里存的两样东西：
///   1. 设备 id（iOS 是系统给的 UUID，Android 是 MAC）
///   2. 设备名（id 变了还能靠名字兜一下，比如换机重装）
class Prefs {
  static const _kCtrlId = 'ctrl_device_id';
  static const _kCtrlName = 'ctrl_device_name';
  static const _kCtrlChannel = 'ctrl_channel';
  static const _kBmsId = 'bms_device_id';
  static const _kBmsName = 'bms_device_name';
  static const _kBmsChannel = 'bms_channel';
  static const _kAutoConnect = 'auto_connect';
  static const _kPolePairs = 'fardriver_pole_pairs';
  static const _kPollMs = 'poll_ms';
  static const _kShowAll = 'show_all';
  static const _kUpdateCheck = 'update_check_at';

  late SharedPreferences _sp;

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
  }

  String? deviceId(String role) => _sp.getString(role == 'controller' ? _kCtrlId : _kBmsId);
  String? deviceName(String role) => _sp.getString(role == 'controller' ? _kCtrlName : _kBmsName);

  Future<void> saveDevice(String role, String id, String name) async {
    await _sp.setString(role == 'controller' ? _kCtrlId : _kBmsId, id);
    await _sp.setString(role == 'controller' ? _kCtrlName : _kBmsName, name);
  }

  Future<void> forget(String role) async {
    await _sp.remove(role == 'controller' ? _kCtrlId : _kBmsId);
    await _sp.remove(role == 'controller' ? _kCtrlName : _kBmsName);
    await _sp.remove(role == 'controller' ? _kCtrlChannel : _kBmsChannel);
  }

  /// 上次跑通的写入信道（特征 UUID 短名）
  String? channel(String role) => _sp.getString(role == 'controller' ? _kCtrlChannel : _kBmsChannel);

  Future<void> saveChannel(String role, String? key) async {
    if (key == null) {
      await _sp.remove(role == 'controller' ? _kCtrlChannel : _kBmsChannel);
    } else {
      await _sp.setString(role == 'controller' ? _kCtrlChannel : _kBmsChannel, key);
    }
  }

  bool get autoConnect => _sp.getBool(_kAutoConnect) ?? true;
  set autoConnect(bool v) => _sp.setBool(_kAutoConnect, v);

  bool get showAll => _sp.getBool(_kShowAll) ?? false;
  set showAll(bool v) => _sp.setBool(_kShowAll, v);

  int get polePairs {
    final v = _sp.getInt(_kPolePairs) ?? 20;
    return v > 0 ? v : 20;
  }

  set polePairs(int v) => _sp.setInt(_kPolePairs, v);

  int get pollMs {
    final v = _sp.getInt(_kPollMs) ?? 400;
    return v.clamp(200, 2000);
  }

  set pollMs(int v) => _sp.setInt(_kPollMs, v.clamp(200, 2000));

  /// 上次检查更新的时间戳（毫秒）。自动检查按这个做节流，别每切回前台就打一次 API
  /// —— GitHub 未授权接口 60 次/小时，打爆了就是一段时间内彻底查不到。
  int get lastUpdateCheck => _sp.getInt(_kUpdateCheck) ?? 0;

  Future<void> markUpdateChecked() =>
      _sp.setInt(_kUpdateCheck, DateTime.now().millisecondsSinceEpoch);

  /// 自动检查是否该跑了（默认 6 小时一次）
  bool shouldCheckUpdate({Duration every = const Duration(hours: 6)}) {
    final last = lastUpdateCheck;
    if (last == 0) return true;
    return DateTime.now().millisecondsSinceEpoch - last >= every.inMilliseconds;
  }

  Map<String, dynamic> debugDump() => {
        'ctrl': deviceName('controller'),
        'bms': deviceName('bms'),
        'auto': autoConnect,
      };

  String encode(List<int> bytes) => base64Encode(bytes);
}
