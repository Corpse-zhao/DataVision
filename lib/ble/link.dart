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

/// 链路自愈的几条判定阈值。
///
/// 抽成纯函数是为了能单测 —— 这些阈值写错的表现很隐蔽（连上了、界面绿点、
/// 但一条数据都没有），只能靠测试兜住。
class LinkPolicy {
  /// 连上后多久还是 0 字节就断开重连（重走服务发现 + 订阅）
  static const zeroByteSeconds = 20;

  /// 还没坐实的信道，多久没数据就换下一条
  static const channelWindowMs = 1500;

  /// 探测命中的那条多给点时间（坐实要两帧）
  static const channelWindowHitMs = 3000;

  /// 同一条信道上连出这么多帧才算坐实，才敢写进本地记忆
  static const confirmedFrames = 2;

  static bool switchChannel({
    required bool confirmed,
    required int channels,
    required Duration sinceChannel,
    required int windowMs,
  }) => !confirmed && channels > 1 && sinceChannel.inMilliseconds > windowMs;

  static bool reconnectZeroByte({
    required int rxCount,
    required Duration sinceLink,
  }) => rxCount == 0 && sinceLink.inSeconds >= zeroByteSeconds;
}

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

  /// 订阅到的通知口（数据台里显示，排查「一个字节都收不到」用）
  String notifyInfo = '';
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
  int _reconnectAttempt = 0;
  bool _gotFrame = false;
  bool _disposed = false;
  DateTime? _lastRawNotifyAt;

  /// 每解析出一帧就 +1（探测信道时用来判断「这个等待窗口里有没有回帧」）
  int _frameSeq = 0;

  /// 当前信道上连续收到几帧。>=2 才算这条信道坐实，才敢写进本地记忆
  int _framesOnChannel = 0;

  /// 当前信道给多久没数据就换下一条
  int _channelWindowMs = LinkPolicy.channelWindowMs;

  /// 本次连接开始的时间（判断「连上了但一个字节都没有」）
  DateTime _linkStartedAt = DateTime.now();

  /// 连续几次连上后 0 字节（>=2 次就把信道记忆清掉，别再信上次记的那条）
  int _zeroByteLinks = 0;

  bool get _channelConfirmed => _framesOnChannel >= LinkPolicy.confirmedFrames;

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
      } else if (state == BluetoothAdapterState.on &&
          phase == LinkPhase.error &&
          error == '蓝牙未打开') {
        _setPhase(LinkPhase.idle, '蓝牙已就绪');
        if (prefs.autoConnect && hasSaved) startScan(auto: true);
      }
    });
  }

  // MARK: - 扫描

  Future<void> startScan({bool auto = false}) async {
    if (connected || _disposed) return;
    if (_scanSub == null) {
      _scanSub = ScanBus.instance.stream.listen(
        _onScan,
        onError: (e) {
          error = '$e';
          notifyListeners();
        },
      );
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
    if (id == null && name != null && name.isNotEmpty && _nameOf(r) == name)
      return true;
    return false;
  }

  // MARK: - 连接

  Future<void> connect(ScanResult r) => connectDevice(r.device);

  Future<void> connectDevice(BluetoothDevice device) async {
    if (phase == LinkPhase.connecting) return;
    await stopScan();
    _device = device;
    deviceName = device.platformName.isNotEmpty
        ? device.platformName
        : device.advName;
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
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {}
    }

    // 连上就记住：哪怕协议还没认出来，下次也要能自动连回来
    final rid = device.remoteId.str;
    final nm = deviceName.isEmpty ? '未命名设备' : deviceName;
    if (prefs.deviceId(role) != rid || prefs.deviceName(role) != nm) {
      prefs.saveDevice(role, rid, nm);
      _log('!', '已记住 $nm，下次搜到自动连接');
    }

    _subs.add(
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !_disposed) {
          _onDisconnected();
        }
      }),
    );

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
    // 驱动是复用的实例（重连时不重建），把上一轮残留的半截帧清掉
    driver?.reset();
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

    // 订阅所有可通知口（点名的排前面）。
    //
    // v1.0.10 曾为了「省带宽」只订驱动点名的那一个，代价是同一型号不同固件
    // 把数据放在别的通知口上的板子直接一条字节都收不到（现场：ANT-BLE24EAUB
    // 有 8 个可写口，数据不在 FFE1 上）。多订一个口本身不花带宽 —— 只有板子
    // 真往那儿发才有开销，而那种情况本来就是我们要的数据。
    final notifyHints = driver?.notifyHints ?? const <String>[];
    final hinted = notify
        .where((c) => notifyHints.contains(shortUuid(c.uuid.str)))
        .toList();
    final targets = <BluetoothCharacteristic>[
      ...hinted,
      ...notify.where((c) => !hinted.contains(c)),
    ];
    final subscribed = <String>[];
    for (final c in targets) {
      try {
        await c.setNotifyValue(true);
        _subs.add(c.onValueReceived.listen((data) => feedInput(data, c)));
        subscribed.add(shortUuid(c.uuid.str));
      } catch (e) {
        _log('!', '订阅 ${shortUuid(c.uuid.str)} 失败：$e');
      }
    }
    if (subscribed.isEmpty) {
      _setPhase(LinkPhase.error, '一个通知口都订不上');
      return;
    }
    notifyInfo = '${subscribed.length} 个（${subscribed.join('、')}）';
    _log('!', '订阅通知口 $notifyInfo');

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
      if ((c.properties.notify || c.properties.indicate) &&
          !ordered.contains(c))
        ordered.add(c);
    }
    for (final c in writable) {
      if (!ordered.contains(c)) ordered.add(c);
    }

    // 上次跑通的那条排最前
    final savedChannel = prefs.channel(role);
    if (savedChannel != null) {
      final idx = ordered.indexWhere(
        (c) => shortUuid(c.uuid.str) == savedChannel,
      );
      if (idx > 0) ordered.insert(0, ordered.removeAt(idx));
    }

    _writeChars.addAll(ordered);
    channelCount = _writeChars.length;
    channelIndex = 0;
    _writeChar = _writeChars.isEmpty ? null : _writeChars.first;
    _channelStartedAt = DateTime.now();
    _linkStartedAt = DateTime.now();
    _tick = 0;
    _probeDriverIdx = 0;
    _gotFrame = false;
    _framesOnChannel = 0;
    _channelWindowMs = LinkPolicy.channelWindowMs;
    _staleHits = 0;
    _lastFrameAt = null;

    if (driver?.passive ?? false) {
      channelCount = 0;
      gattInfo = '被动接收（设备自己推，不用发请求）';
    }
    _updateGattInfo();
    _setPhase(LinkPhase.ready, '已连接，等数据');
    _log('!', '写入信道 ${channelCount} 条，先用第 1 条');

    // 有些板子要握手命令才肯吐数据；试探完一定要把轮询开起来，
    // 否则一次卡住的写入就会让整条链路「连着但永远没数据」。
    final d = driver ?? pool.first;
    try {
      for (final f in d.initialFrames) {
        await _write(f);
      }
      await _probeChannels();
    } finally {
      _startPolling();
    }
  }

  /// 单次写入：带超时，失败先试另一种写方式，再不行就算这条信道不对。
  ///
  /// 必须带超时 —— 有些特征标着「无需响应」实际要 ack，`await write()` 会一直挂着，
  /// 把后面的 `_startPolling()` 一起拖死，表现就是「连上了但一条数据都没有」。
  Future<void> _safeWrite(
    BluetoothCharacteristic c,
    List<int> bytes, {
    int timeoutMs = 400,
  }) async {
    final first = c.properties.writeWithoutResponse;
    for (final noResp in [first, !first]) {
      try {
        await c
            .write(bytes, withoutResponse: noResp)
            .timeout(Duration(milliseconds: timeoutMs));
        return;
      } catch (_) {
        // 换另一种方式再试一次
      }
    }
  }

  /// 连上后逐条信道试着发一帧，谁先回数据就锁谁。
  ///
  /// 一次只写一条、写完等 700ms —— 这样「回帧」和「哪条信道」是对得上的。
  /// v1.0.10 是三条一起发（间隔 120ms），回帧时根本分不清是哪条通的，
  /// 锁错信道之后就一条数据都没有，还得靠重连才缓过来。
  Future<void> _probeChannels() async {
    final d = driver;
    if (d == null || d.passive || _writeChars.isEmpty) return;
    final frames = d.initialFrames.isNotEmpty
        ? d.initialFrames
        : d.pollFrames(1);
    if (frames.isEmpty) return;

    for (var i = 0; i < _writeChars.length; i++) {
      final c = _writeChars[i];
      // 上次跑通的那条排在 0，一般第一条就中，不用再挨个试
      for (final f in frames) {
        await _safeWrite(c, f);
      }
      _writeChar = c;
      channelIndex = i;
      _channelStartedAt = DateTime.now();
      if (await _waitForFrame(const Duration(milliseconds: 700))) {
        _framesOnChannel = 1;
        _channelWindowMs = LinkPolicy.channelWindowHitMs; // 命中的信道多给点时间坐实
        _updateGattInfo();
        _log('!', '信道命中 ${i + 1}/$channelCount（${shortUuid(c.uuid.str)}）');
        return;
      }
    }
    // 一条都没回：从第一条开始轮询，靠 _onTick 的轮转继续找
    channelIndex = 0;
    _writeChar = _writeChars.first;
    _channelStartedAt = DateTime.now();
    _updateGattInfo();
  }

  /// 等一小段时间看有没有新帧进来（探测信道用）
  Future<bool> _waitForFrame(Duration d) async {
    final start = _frameSeq;
    final deadline = DateTime.now().add(d);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (_frameSeq != start) return true;
    }
    return false;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final ms = (driver?.pollIntervalMs ?? prefs.pollMs).clamp(150, 2000);
    _pollTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _onTick());
  }

  Future<void> _onTick() async {
    if (!connected || _disposed) return;
    _tick++;

    // ① 连上 20 秒一个字节都没收到：多半是通知口没订上 / 信道全错。
    //    断开重连会重走 discoverServices + 订阅，比在原地换信道有用得多。
    if (LinkPolicy.reconnectZeroByte(
      rxCount: rxCount,
      sinceLink: DateTime.now().difference(_linkStartedAt),
    )) {
      _zeroByteLinks++;
      if (_zeroByteLinks >= 2) {
        // 连续两次都 0 字节，说明本地记的那条信道是错的，清掉
        prefs.saveChannel(role, null);
        _log('!', '连着两次一个字节都没收到，清掉信道记忆重新找');
      } else {
        _log('!', '连上后一直没收到字节，重连一次（重新订阅）');
      }
      await _hardReconnect();
      return;
    }

    // ② 信道还没坐实（同一条上没连出两帧）：到窗口就换下一条，整轮 8 条也会走完
    if (LinkPolicy.switchChannel(
      confirmed: _channelConfirmed,
      channels: _writeChars.length,
      sinceChannel: DateTime.now().difference(_channelStartedAt),
      windowMs: _channelWindowMs,
    )) {
      _nextChannel();
      return;
    }

    // ③ 曾经稳定过（某条信道上连出过两帧）但现在停了：先换信道，两次不行就重连
    if (_channelConfirmed && _lastFrameAt != null) {
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

    // 驱动没定下来：每 2.5 秒换一个驱动试探
    if (driver == null) {
      final now = DateTime.now();
      if (_lastProbeDriverAt == null ||
          now.difference(_lastProbeDriverAt!).inMilliseconds > 2500) {
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
    _writeChar = _writeChars[channelIndex];
    _channelStartedAt = DateTime.now();
    _framesOnChannel = 0;
    _channelWindowMs = LinkPolicy.channelWindowMs;
    _updateGattInfo();
  }

  Future<void> _write(List<int> bytes) async {
    final c = _writeChar;
    if (c == null) return;
    try {
      await c
          .write(bytes, withoutResponse: c.properties.writeWithoutResponse)
          .timeout(const Duration(milliseconds: 400));
    } catch (e) {
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
      _frameSeq++;
      _framesOnChannel++;
      _gotFrame = true;
      _staleHits = 0;
      _zeroByteLinks = 0;
      _lastFrameAt = DateTime.now();
      frameCount++;
      _reconnectAttempt = 0;
      error = null;
      if (phase != LinkPhase.online) _setPhase(LinkPhase.online, '在线');
      // 信道坐实（同一条上连出两帧）才写进本地，免得把碰巧回了一帧的错信道记死
      if (_channelConfirmed) _persistLock();
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
    _framesOnChannel = 0;
    _staleHits = 0;
    notifyInfo = '';
    // 驱动里可能留着上一轮没收完的半截帧，不清理会让新连接从错位处开始解析
    driver?.reset();
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
    final delay = Duration(
      milliseconds: (900 * _reconnectAttempt).clamp(900, 6000),
    );
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
