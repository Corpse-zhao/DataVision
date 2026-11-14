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

  Stream<List<ScanResult>> get stream => _controller.stream;

  Future<void> join(Object owner) async {
    _refs.add(owner);
    _sub ??= FlutterBluePlus.onScanResults.listen(
      (r) {
        if (!_controller.isClosed) _controller.add(r);
      },
      onError: (_) {},
    );
    _kicker ??= Timer.periodic(const Duration(seconds: 7), (_) => _kick());
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

  Future<void> _kick() async {
    if (_starting) return;
    if (FlutterBluePlus.isScanningNow) return;
    _starting = true;
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 6),
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
