import '../core/models.dart';
import 'driver.dart';

/// 凌博（LBMC）控制器协议
///
/// 帧结构 `AA 55 LEN CMD data… SUM8`，总长 = LEN + 3，SUM8 = 前面所有字节之和的低 8 位。
/// BLE：服务 FFF0，写 FFF2，通知 FFF1。
///
/// - `AA 55 02 20 21` 读标定（拿母线电压/电流的换算分母，所以 E300/E400 各电压平台通用）
/// - `AA 55 02 22 23` 读实时
class LingboDriver extends DeviceDriver {
  static const calibrationRequest = [0xAA, 0x55, 0x02, 0x20, 0x21];
  static const realtimeRequest = [0xAA, 0x55, 0x02, 0x22, 0x23];

  final List<int> _stream = [];
  int _divV = 0;
  int _divI = 0;
  int _phaseBaseV = 0;
  int _phaseBaseI = 0;
  int _mode = 0;
  int _torqueMax = 0;
  bool _calibrated = false;
  int _frameNo = 0;
  ControllerData? _data;
  List<int> _last = const [];

  @override
  String get id => 'lingbo';
  @override
  String get name => '凌博 LBMC';
  @override
  DriverKind get kind => DriverKind.controller;
  @override
  List<String> get nameHints => const ['LBMC', 'LINGBO'];
  @override
  List<String> get serviceHints => const ['FFF0', 'FF00'];
  @override
  List<String> get notifyHints => const ['FFF1'];
  @override
  List<String> get writeHints => const ['FFF2', 'FFF1', 'FFF0'];
  @override
  int get pollIntervalMs => 400;

  @override
  List<List<int>> pollFrames(int tick) {
    if (!_calibrated) return const [calibrationRequest];
    // 标定值偶尔会因模块复位丢掉，20 轮补读一次
    if (tick % 20 == 0) return const [calibrationRequest, realtimeRequest];
    return const [realtimeRequest];
  }

  @override
  void reset() {
    _stream.clear();
    _divV = 0;
    _divI = 0;
    _calibrated = false;
    _frameNo = 0;
    _data = null;
    _last = const [];
  }

  @override
  ControllerData? get controllerData => _data;
  @override
  List<int> get lastFrame => _last;

  @override
  String get detail {
    if (!_calibrated) return '未标定（等 0x60 帧）';
    return '标定 电压÷$_divV 电流÷$_divI · 相基准 $_phaseBaseI/$_phaseBaseV · 模式 $_mode · 扭矩上限 $_torqueMax';
  }

  @override
  bool feed(List<int> chunk) {
    if (chunk.isEmpty) return false;
    _stream.addAll(chunk);
    if (_stream.length > 512) _stream.removeRange(0, _stream.length - 512);

    var parsed = false;
    var i = 0;
    while (_stream.length - i >= 5) {
      if (_stream[i] != 0xAA || _stream[i + 1] != 0x55) {
        i++;
        continue;
      }
      final len = _stream[i + 2];
      final frameLen = len + 3;
      if (len < 2 || frameLen > 160) {
        i++;
        continue;
      }
      if (_stream.length - i < frameLen) break;
      final frame = _stream.sublist(i, i + frameLen);
      final sum = frame.take(frameLen - 1).fold<int>(0, (a, b) => (a + b) & 0xFF);
      if (sum != frame[frameLen - 1]) {
        i++;
        continue;
      }
      if (frame[3] == 0x60) {
        _applyCalibration(frame);
      } else if (frame[3] == 0x62 && _calibrated && frame.length >= 23) {
        _parseRealtime(frame);
        _last = frame;
        parsed = true;
      }
      i += frameLen;
    }
    if (i > 0) _stream.removeRange(0, i);
    return parsed;
  }

  void _applyCalibration(List<int> f) {
    if (f.length < 16) return;
    final divI = u16le(f, 8);
    final divV = u16le(f, 10);
    if (divI > 0 && divV > 0) {
      _phaseBaseI = u16le(f, 4);
      _phaseBaseV = u16le(f, 6);
      _divI = divI;
      _divV = divV;
      _mode = f[12];
      _torqueMax = u16le(f, 13);
      _calibrated = true;
    } else {
      _calibrated = false;
    }
  }

  void _parseRealtime(List<int> f) {
    final rpm = i16le(f, 4).abs();
    final volts = u16le(f, 10) / _divV;
    final amps = i16le(f, 12) / _divI;
    final power = volts * amps;

    double? ctrlT = i16le(f, 14).toDouble();
    if (ctrlT < -60 || ctrlT > 200) ctrlT = null;
    double? motorT = i16le(f, 16).toDouble();
    if (motorT < -60 || motorT > 200) motorT = null;

    // 转把 @22（0.01V）；挡位 @27（标准 29 字节帧才有）
    double? thrV;
    double? thrPct;
    if (f.length >= 24) {
      final v = u16le(f, 22) * 0.01;
      if (v >= 0 && v <= 4.95) {
        thrV = v;
        thrPct = ((v - 0.85) / (4.2 - 0.85) * 100).clamp(0, 100).toDouble();
      }
    }
    int? gear;
    if (f.length >= 29) gear = f[27] & 0x0F;

    final fault = u32le(f, 18);
    final phaseRaw = u16le(f, 6);
    final phaseA = phaseRaw > 0 ? _sqrt(phaseRaw) : 0.0;

    _frameNo++;
    final (pVal, pUnit) = fmtPower(power);

    _data = ControllerData(
      at: DateTime.now(),
      model: '凌博 ${_mode == 0 ? 'FOC' : '模式$_mode'}',
      frameCount: _frameNo,
      primary: [
        Metric('母线电压', volts.toStringAsFixed(1), 'V'),
        Metric('母线电流', amps.toStringAsFixed(1), 'A'),
        Metric('功率', pVal, pUnit),
        Metric('转速', '$rpm', 'rpm'),
      ],
      secondary: [
        Metric('控制器温度', fmtNum(ctrlT, 0), '℃',
            tone: (ctrlT ?? 0) > 80 ? MetricTone.warn : MetricTone.normal),
        Metric('电机温度', fmtNum(motorT, 0), '℃',
            tone: (motorT ?? 0) > 100 ? MetricTone.warn : MetricTone.normal),
        Metric('转把', fmtNum(thrPct, 0), '%'),
        Metric('转把电压', fmtNum(thrV, 2), 'V'),
        Metric('挡位', fmtInt(gear), ''),
        Metric('相电流(估)', phaseA.toStringAsFixed(1), 'A'),
        Metric('故障位', '0x${fault.toRadixString(16).toUpperCase().padLeft(8, '0')}', '',
            tone: fault == 0 ? MetricTone.good : MetricTone.bad),
        Metric('帧长', '${f.length}', 'B'),
      ],
      fault: fault == 0 ? null : '故障位 0x${fault.toRadixString(16).toUpperCase()}',
    );
  }

  double _sqrt(int v) {
    var x = v.toDouble();
    if (x <= 0) return 0;
    var z = (x + 1) / 2;
    for (var k = 0; k < 12; k++) {
      z = (z + x / z) / 2;
    }
    return z;
  }
}
