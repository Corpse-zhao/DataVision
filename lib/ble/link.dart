import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/models.dart';
import '../core/prefs.dart';
import '../drivers/driver.dart';
import '../drivers/fardriver.dart';
import '../drivers/registry.dart';
import '../drivers/vesc.dart';
import 'scanner.dart';

enum LinkPhase { idle, scanning, connecting, ready, online, error }

class LinkLog {
  final DateTime at;
  final String tag; // '→' 发送 / '←' 收到 / '!' 状态
  final String text;
  LinkLog(this.tag, this.text) : at = DateTime.now();
}

/// 一条 BLE 链路（控制器一条、保护板一条，互不干扰）。
///
/// 它负责三件难事：
///   1. 自动连：记住上次的设备，扫到就自己连，不用每次点
///   2. 信道回退：写入通道按优先级排，第一条不回数据就换第二条、第三条
///   3. 断电重连：掉线自动扫回来，不会停在「已断开」死等
class BleLink extends ChangeNotifier {
  BleLink({required this.role, required this.pool, required this.prefs});

  final String role; // 'controller' | 'bms'
  final List<DeviceDriver> pool;
  final Prefs prefs;

  LinkPhase phase = LinkPhase.idle;
  String status = '未连接';
  String deviceName = '';
  String? error;

  /// 锁定的驱动（按住第一帧解析成功的那个）
  DeviceDriver? driver;

  /// 扫描列表
  final List<ScanResult> results = [];

  int channelIndex = 0;
  int channelCount = 0;
  String channelName = '';

  int rxBytes = 0;
  int rxCount = 0;
  String lastHex = '';
  String gattInfo = '';
  int frameCount = 0;

  final List<LinkLog> logs = [];

  BluetoothDevice? _device;
  final List<StreamSubscription> _subs = [];
  final List<BluetoothCharacteristic> _writeChars = [];
  BluetoothCharacteristic? _writeChar;
  Timer? _pollTimer;
  Timer? _rescanTimer;
  Timer? _reconnectTimer;
  Timer? _scanWindowTimer;
  StreamSubscription? _scanSub;
  StreamSubscription? _adapterSub;
  bool _joinedBus = false;
  int _tick = 0;
  int _probeDriverIdx = 0;
  DateTime _channelStartedAt = DateTime.now();
  DateTime? _lastFrameAt;
  DateTime? _lastProbeDriverAt;
  int _staleHits = 0;
  int _channelRounds = 0;
  int _reconnectAttempt = 0;
  bool _gotFrame = false;
  bool _disposed = false;
  DateTime? _lastProbeAt;
  int _lastProbeIdx = 0;
  DateTime? _lastRawNotifyAt;

  bool get connected => _device?.isConnected ?? false;
  bool get isScanning => _scanning;
  bool _scanning = false;

  ControllerData? get controller => driver?.controllerData;
  BmsData? get bms => driver?.bmsData;

  String get savedName => prefs.deviceName(role) ?? '';
  bool get hasSaved => prefs.deviceId(role) != null;

  void _log(String tag, String text) {
    logs.insert(0, LinkLog(tag, text));
    if (logs.length > 120) logs.removeLast();
    notifyListeners();
  }

  void _setPhase(LinkPhase p, String s) {
    phase = p;
    status = s;
    notifyListeners();
  }

  // MARK: - 生命周期

  Future<void> init() async {
    FlutterBluePlus.setLogLevel(LogLevel.error, color: false);
    _watchAdapter();
    if (prefs.autoConnect && hasSaved) {
      _log('!', '已记住 ${prefs.deviceName(role) ?? ''}，自动搜索中');
      await startScan(auto: true);
    } else {
      _setPhase(LinkPhase.idle, hasSaved ? '待连接' : '未配对');
    }
  }

  void _watchAdapter() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        _setPhase(LinkPhase.error, '蓝牙未打开');
      } else if (state == BluetoothAdapterState.on && phase == LinkPhase.error && error == '蓝牙未打开') {
        _setPhase(LinkPhase.idle, '蓝牙已就绪');
        if (prefs.autoConnect && hasSaved) startScan(auto: true);
      }
    });
  }

  // MARK: - 扫描

  Future<void> startScan({bool auto = false}) async {
    if (connected || _disposed) return;
    if (_scanSub == null) {
      _scanSub = ScanBus.instance.stream.listen(_onScan, onError: (e) {
        error = '$e';
        notifyListeners();
      });
    }
    _joinedBus = true;
    _setPhase(LinkPhase.scanning, '搜索中');
    await ScanBus.instance.join(this);
  }

  Future<void> stopScan() async {
    _rescanTimer?.cancel();
    _rescanTimer = null;
    if (_joinedBus) {
      _joinedBus = false;
      await ScanBus.instance.leave(this);
    }
    _scanning = false;
    if (phase == LinkPhase.scanning) _setPhase(LinkPhase.idle, '待连接');
    notifyListeners();
  }

  void _onScan(List<ScanResult> list) {
    // 手动点开列表时，把看起来像目标设备的排前面
    results
      ..clear()
      ..addAll(list);
    results.sort((a, b) {
      final pa = _rank(a);
      final pb = _rank(b);
      if (pa != pb) return pa.compareTo(pb);
      return b.rssi.compareTo(a.rssi);
    });

    if (prefs.autoConnect && hasSaved) {
      final hit = list.where(_isSaved).toList();
      if (hit.isNotEmpty && !connected && phase != LinkPhase.connecting) {
        _log('!', '找到已记住的设备：${_nameOf(hit.first)}');
        connectDevice(hit.first.device);
      }
    }
    notifyListeners();
  }

  int _rank(ScanResult r) {
    final n = _nameOf(r).toUpperCase();
    for (final d in pool) {
      for (final h in d.nameHints) {
        if (n.contains(h)) return 0;
      }
    }
    for (final d in pool) {
      for (final h in d.serviceHints) {
        if (_servicesOf(r).contains(h)) return 0;
      }
    }
    return 1;
  }

  String _nameOf(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    final p = r.device.platformName;
    return p.isEmpty ? '未知设备' : p;
  }

  List<String> _servicesOf(ScanResult r) =>
      r.advertisementData.serviceUuids.map((g) => shortUuid(g.str)).toList();

  bool _isSaved(ScanResult r) {
    final id = prefs.deviceId(role);
    final name = prefs.deviceName(role);
    if (id != null && r.device.remoteId.str == id) return true;
    // iOS 重装后 UUID 会变，名字没变也认
    if (id == null && name != null && name.isNotEmpty && _nameOf(r) == name) return true;
    return false;
  }

  // MARK: - 连接

  Future<void> connect(ScanResult r) => connectDevice(r.device);

  Future<void> connectDevice(BluetoothDevice device) async {
    if (phase == LinkPhase.connecting) return;
    await stopScan();
    _device = device;
    deviceName = device.platformName.isNotEmpty ? device.platformName : device.advName;
    await _teardownGatt();
    _setPhase(LinkPhase.connecting, '连接中');
    _log('!', '连接 $deviceName');

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: 247,
      );
    } catch (e) {
      error = '$e';
      _setPhase(LinkPhase.error, '连接失败');
      _log('!', '连接失败：$e');
      _scheduleReconnect();
      return;
    }

    // Android 默认给 balanced 连接参数（30~50ms 一个连接事件），
    // 蚂蚁板这种 152 字节 / 8 包的长帧容易被拖慢；high 档能明显缩短单帧时间。
    // iOS 没有这个接口，失败也不影响连接本身。
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
      } catch (_) {}
    }

    // 连上就记住：哪怕协议还没认出来，下次也要能自动连回来
    final rid = device.remoteId.str;
    final nm = deviceName.isEmpty ? '未命名设备' : deviceName;
    if (prefs.deviceId(role) != rid || prefs.deviceName(role) != nm) {
      prefs.saveDevice(role, rid, nm);
      _log('!', '已记住 $nm，下次搜到自动连接');
    }

    _subs.add(device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_disposed) {
        _onDisconnected();
      }
    }));

    await _setupGatt(device);
  }

  Future<void> _setupGatt(BluetoothDevice device) async {
    _setPhase(LinkPhase.ready, '已连接，读服务');
    List<BluetoothService> services;
    try {
      services = await device.discoverServices();
    } catch (e) {
      _setPhase(LinkPhase.error, '读服务失败');
      _log('!', '读服务失败：$e');
      return;
    }

    final gattShort = <String>[];
    final notify = <BluetoothCharacteristic>[];
    final writable = <BluetoothCharacteristic>[];
    for (final s in services) {
      gattShort.add(shortUuid(s.uuid.str));
      for (final c in s.characteristics) {
        final p = c.properties;
        if (p.notify || p.indicate) notify.add(c);
        if (p.write || p.writeWithoutResponse) writable.add(c);
      }
    }

    // 先按名字/服务定驱动，定不下来就靠首帧嗅探（见 feedInput）
    final byName = pickByName(pool, deviceName);
    final bySvc = pickByServices(pool, [...gattShort, ...gattShort]);
    driver = byName ?? bySvc;
    _applyPrefs(driver);
    if (driver != null) {
      _log('!', '驱动：${driver!.name}');
    } else {
      _log('!', '没认出品牌，进入嗅探模式（发试探帧 + 等首帧）');
    }

    if (notify.isEmpty) {
      _setPhase(LinkPhase.error, '这个设备没有通知通道');
      return;
    }

    // 只订驱动点名的通知口；一个都没命中（换了固件 / 不认识）才退回订前 3 个。
    // 原来无差别订阅所有 notify：蚂蚁板有 5~6 个可通知口，多订的只会抢带宽、
    // 拖慢 152 字节长帧的拼装，表现出来就是「数据一顿一顿、偶尔假掉线」。
    final notifyHints = driver?.notifyHints ?? const <String>[];
    final hinted = notify.where((c) => notifyHints.contains(shortUuid(c.uuid.str))).toList();
    final targets = hinted.isNotEmpty ? hinted : notify.take(3).toList();
    for (final c in targets) {
      try {
        await c.setNotifyValue(true);
        _subs.add(c.onValueReceived.listen((data) => feedInput(data, c)));
        _log('!', '订阅 ${shortUuid(c.uuid.str)}');
      } catch (e) {
        _log('!', '订阅 ${shortUuid(c.uuid.str)} 失败：$e');
      }
    }

    // 写入信道排序：驱动提示优先级 → 读写合一 → 其余可写
    _writeChars.clear();
    final hints = <String>{};
    if (driver != null) hints.addAll(driver!.writeHints);
    for (final d in pool) {
      hints.addAll(d.writeHints);
    }
    final hintList = hints.toList();
    final ordered = <BluetoothCharacteristic>[];
    for (final h in hintList) {
      for (final c in writable) {
        if (shortUuid(c.uuid.str) == h && !ordered.contains(c)) ordered.add(c);
      }
    }
    for (final c in writable) {
      if ((c.properties.notify || c.properties.indicate) && !ordered.contains(c)) ordered.add(c);
    }
    for (final c in writable) {
      if (!ordered.contains(c)) ordered.add(c);
    }

    // 上次跑通的那条排最前
    final savedChannel = prefs.channel(role);
    if (savedChannel != null) {
      final idx = ordered.indexWhere((c) => shortUuid(c.uuid.str) == savedChannel);
      if (idx > 0) ordered.insert(0, ordered.removeAt(idx));
    }

    _writeChars.addAll(ordered);
    channelCount = _writeChars.length;
    channelIndex = 0;
    _writeChar = _writeChars.isEmpty ? null : _writeChars.first;
    _channelStartedAt = DateTime.now();
    _tick = 0;
    _probeDriverIdx = 0;
    _gotFrame = false;
    _staleHits = 0;

    if (driver?.passive ?? false) {
      channelCount = 0;
      gattInfo = '被动接收（设备自己推，不用发请求）';
    }
    _updateGattInfo();
    _setPhase(LinkPhase.ready, '已连接，等数据');
    _log('!', '写入信道 ${channelCount} 条，先用第 1 条');

    // 有些板子要握手命令才肯吐数据
    final d = driver ?? pool.first;
    for (final f in d.initialFrames) {
      await _write(f);
    }

    await _probeChannels();
    _startPolling();
  }

  /// 连上后先向最多 3 条可写信道各发一帧（间隔 120ms）。
  ///
  /// 蚂蚁板「三条信道只有一条能写」：原先是 1.6 秒才换一条，正确的那条排第 3 位
  /// 就得等将近 5 秒才出第一帧。一起试探后，正确那条一般几百毫秒就回数据，
  /// 收到首帧时再把信道锁到「最后发出去的那条」。
  Future<void> _probeChannels() async {
    final d = driver;
    if (d == null || d.passive || _writeChars.length <= 1) return;
    final frames = d.initialFrames.isNotEmpty ? d.initialFrames : d.pollFrames(1);
    if (frames.isEmpty) return;

    final n = _writeChars.length < 3 ? _writeChars.length : 3;
    for (var i = 0; i < n; i++) {
      final c = _writeChars[i];
      for (final f in frames) {
        try {
          await c.write(f, withoutResponse: c.properties.writeWithoutResponse);
        } catch (_) {
          // 这条写不动就先放过，后面按原逻辑回退
        }
      }
      _lastProbeAt = DateTime.now();
      _lastProbeIdx = i;
      if (i < n - 1) await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    // 试探完把当前信道放回原来那条，等首帧回来再由 _commitProbedChannel 定
    _writeChar = _writeChars[channelIndex.clamp(0, _writeChars.length - 1)];
    _channelStartedAt = DateTime.now();
  }

  /// 首帧回来时，如果刚做过信道试探，就锁到最后发出去的那条上
  void _commitProbedChannel() {
    final at = _lastProbeAt;
    if (at == null || _writeChars.length <= 1) return;
    if (DateTime.now().difference(at).inMilliseconds > 900) return;
    if (_lastProbeIdx >= _writeChars.length) return;
    _lastProbeAt = null;
    channelIndex = _lastProbeIdx;
    _writeChar = _writeChars[channelIndex];
    _channelStartedAt = DateTime.now();
    _updateGattInfo();
    _log('!', '信道锁定 ${channelIndex + 1}/$channelCount（试探命中）');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final ms = (driver?.pollIntervalMs ?? prefs.pollMs).clamp(150, 2000);
    _pollTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _onTick());
  }

  Future<void> _onTick() async {
    if (!connected || _disposed) return;
    _tick++;

    // 假在线：连着但 6 秒没有一帧 —— 先换信道，两次都不行就重连
    if (_gotFrame && _lastFrameAt != null) {
      final gap = DateTime.now().difference(_lastFrameAt!);
      if (gap.inSeconds >= (driver?.staleTimeoutSeconds ?? 6)) {
        _staleHits++;
        if (_staleHits <= 2 && _writeChars.length > 1) {
          _nextChannel();
          _log('!', '数据停了，换到信道 ${channelIndex + 1}/$channelCount');
        } else {
          _log('!', '重连中…');
          await _hardReconnect();
        }
        return;
      }
    }

    // 还没出数据：一条信道试 1.6 秒，不行换下一条
    if (!_gotFrame && _writeChars.length > 1) {
      final windowMs = _channelRounds == 0 ? 1000 : 1600;
      if (DateTime.now().difference(_channelStartedAt).inMilliseconds > windowMs) {
        _nextChannel();
      }
    }

    // 驱动没定下来：每 2.5 秒换一个驱动试探
    if (driver == null) {
      final now = DateTime.now();
      if (_lastProbeDriverAt == null || now.difference(_lastProbeDriverAt!).inMilliseconds > 2500) {
        _lastProbeDriverAt = now;
        _probeDriverIdx = (_probeDriverIdx + 1) % pool.length;
      }
    }

    final d = driver ?? pool[_probeDriverIdx % pool.length];
    if (d.passive) return;
    for (final f in d.pollFrames(_tick)) {
      await _write(f);
    }
  }

  void _nextChannel() {
    if (_writeChars.isEmpty) return;
    channelIndex = (channelIndex + 1) % _writeChars.length;
    if (channelIndex == 0) _channelRounds++;
    _writeChar = _writeChars[channelIndex];
    _channelStartedAt = DateTime.now();
    _updateGattInfo();
  }

  Future<void> _write(List<int> bytes) async {
    final c = _writeChar;
    if (c == null) return;
    final noResp = c.properties.writeWithoutResponse;
    try {
      await c.write(bytes, withoutResponse: noResp);
    } catch (e) {
      if (noResp) {
        try {
          await c.write(bytes, withoutResponse: false);
          return;
        } catch (_) {}
      }
      // 写入失败通常是信道不对，直接换下一条
      if (_writeChars.length > 1) _nextChannel();
    }
  }

  // MARK: - 收数据

  void feedInput(List<int> data, BluetoothCharacteristic from) {
    if (data.isEmpty) return;
    rxBytes += data.length;
    rxCount++;
    lastHex = hex(data, max: 48);

    var parsed = false;
    void tryFeed(DeviceDriver d) {
      if (d.feed(data)) {
        parsed = true;
        if (driver != d) {
          driver = d;
          _applyPrefs(d);
          _log('!', '首帧命中：${d.name}');
          _startPolling();
        }
      }
    }

    final locked = driver;
    if (locked == null) {
      for (final d in pool) {
        tryFeed(d);
      }
    } else {
      // 认定了就只喂它：让别的驱动跟着解析既白耗 CPU，缓冲里还会攒一堆无用字节
      tryFeed(locked);
      // 还没出过帧说明这个驱动只是按广播名猜的，让别的也嗅一眼
      if (!parsed && !_gotFrame) {
        for (final d in pool) {
          if (!identical(d, locked)) tryFeed(d);
        }
      }
    }

    if (parsed) {
      // 首帧可能就是信道试探打出来的，趁热把信道锁定
      _commitProbedChannel();
      _gotFrame = true;
      _staleHits = 0;
      _lastFrameAt = DateTime.now();
      frameCount++;
      _reconnectAttempt = 0;
      error = null;
      if (phase != LinkPhase.online) _setPhase(LinkPhase.online, '在线');
      _persistLock();
      notifyListeners();
    } else if (_rawNotifyAllowed()) {
      // 没解析出整帧的原始字节：数据台看 hex 用，最多 3Hz 刷一次。
      // 蚂蚁板一帧要 8 个通知包，包包都通知就是每秒二十几次全界面重绘。
      notifyListeners();
    }
  }

  bool _rawNotifyAllowed() {
    final now = DateTime.now();
    final last = _lastRawNotifyAt;
    if (last != null && now.difference(last).inMilliseconds < 330) return false;
    _lastRawNotifyAt = now;
    return true;
  }

  /// 跑通之后把「设备 + 信道」记下来，下次开机直接连、直接用对信道
  void _persistLock() {
    final id = _device?.remoteId.str;
    if (id == null) return;
    final name = deviceName.isEmpty ? '未命名' : deviceName;
    if (prefs.deviceId(role) != id || prefs.deviceName(role) != name) {
      prefs.saveDevice(role, id, name);
      _log('!', '已记住 $name，下次搜到自动连接');
    }
    final ch = _writeChar == null ? null : shortUuid(_writeChar!.uuid.str);
    if (ch != null && prefs.channel(role) != ch) {
      prefs.saveChannel(role, ch);
      _log('!', '锁定信道 $ch');
    }
  }

  void _updateGattInfo() {
    if (channelCount == 0) {
      notifyListeners();
      return;
    }
    final n = _writeChar;
    final name = n == null ? '无写入通道' : shortUuid(n.uuid.str);
    gattInfo = '信道 ${channelIndex + 1}/$channelCount：$name';
    notifyListeners();
  }

  /// 把设置页里的参数灌进驱动（极对数这类换算系数）
  void _applyPrefs(DeviceDriver? d) {
    if (d is FardriverDriver) d.polePairs = prefs.polePairs;
    if (d is VescDriver) d.polePairs = prefs.polePairs;
  }

  // MARK: - 断开 / 重连

  void _onDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _writeChar = null;
    _writeChars.clear();
    _gotFrame = false;
    _lastFrameAt = null;
    if (prefs.autoConnect && prefs.deviceId(role) != null) {
      _setPhase(LinkPhase.connecting, '掉线了，自动重连');
      _scheduleReconnect();
    } else {
      _setPhase(LinkPhase.idle, '已断开');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    // 首轮等 1.2 秒再连：掉线的瞬间板子往往还在收尾，立刻直连容易被拒，
    // 一被拒又要等下一轮，看起来就是「怎么都连不上」
    final delay = Duration(milliseconds: (900 * _reconnectAttempt).clamp(900, 6000));
    _reconnectTimer = Timer(delay, () async {
      if (_disposed || connected) return;
      final id = prefs.deviceId(role);
      if (id == null) return;
      // 先直连（iOS/Android 都记得这个 id），失败再扫
      try {
        final dev = BluetoothDevice.fromId(id);
        await connectDevice(dev);
        if (connected) return;
      } catch (_) {}
      await startScan(auto: true);
    });
  }

  Future<void> _hardReconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _onDisconnected();
  }

  Future<void> _teardownGatt() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _writeChars.clear();
    _writeChar = null;
  }

  Future<void> disconnect({bool forget = false}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    await stopScan();
    try {
      await _device?.disconnect();
    } catch (_) {}
    await _teardownGatt();
    if (forget) {
      await prefs.forget(role);
      _log('!', '已清除配对记录');
    }
    _gotFrame = false;
    _setPhase(LinkPhase.idle, '已断开');
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _rescanTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanWindowTimer?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    if (_joinedBus) ScanBus.instance.leave(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
