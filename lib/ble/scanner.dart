import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 全局扫描总线。
///
/// iOS/Android 都只允许一份扫描会话，而本 App 要同时找「控制器」和「保护板」两条链路。
/// 所以扫描只开一份，结果广播给所有订阅者——否则两边各自 startScan 会互相打断
/// （表现就是「只连上一个，另一个永远搜不到」）。
class ScanBus {
  ScanBus._();
  static final ScanBus instance = ScanBus._();

  final _controller = StreamController<List<ScanResult>>.broadcast();
  final _refs = <Object>{};
  StreamSubscription? _sub;
  Timer? _kicker;
  bool _starting = false;
  DateTime? _lastStart;

  Stream<List<ScanResult>> get stream => _controller.stream;

  Future<void> join(Object owner) async {
    _refs.add(owner);
    _sub ??= FlutterBluePlus.onScanResults.listen(
      (r) {
        if (!_controller.isClosed) _controller.add(r);
      },
      onError: (_) {},
    );
    // 20 秒一个窗口：Android 对 startScan 有「30 秒内最多 5 次」的限流，
    // 原来 7 秒一次正好踩在上限，个别机型会直接返回空列表（表现为「搜不到设备」）。
    _kicker ??= Timer.periodic(const Duration(seconds: 20), (_) => _kick());
    await _kick();
  }

  Future<void> leave(Object owner) async {
    _refs.remove(owner);
    if (_refs.isEmpty) {
      _kicker?.cancel();
      _kicker = null;
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  /// 从后台回来时立刻重扫一次（不等下一个 20 秒窗口）。
  /// 4 秒内不重复，避免反复 stop/start 触发限流。
  Future<void> restart() async {
    if (_refs.isEmpty || _starting) return;
    final last = _lastStart;
    if (last != null && DateTime.now().difference(last).inSeconds < 4) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _kick();
  }

  Future<void> _kick() async {
    if (_starting) return;
    if (FlutterBluePlus.isScanningNow) return;
    _starting = true;
    _lastStart = DateTime.now();
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
        continuousUpdates: true,
        androidUsesFineLocation: false,
      );
    } catch (_) {
      // 蓝牙没开 / 没授权：让上层根据 adapterState 提示，不在这里刷屏
    } finally {
      _starting = false;
    }
  }
}
