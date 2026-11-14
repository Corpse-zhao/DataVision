import '../core/models.dart';
import 'driver.dart';

/// VESC 系控制器（Flipsky / MakerX / Trampa / Spintend / 富世华…）
///
/// 这一条覆盖了 DIY 圈绝大多数「开源控制器」：只要刷的是 VESC 固件就通用。
/// 蓝牙走 Nordic UART（NUS）：写 6E400002、通知 6E400003；
/// 报文 `02 LEN payload CRC16(大端) 03`，CRC16-XMODEM（poly 0x1021，初值 0）。
/// 轮询 `COMM_GET_VALUES (0x09)`。
class VescDriver extends DeviceDriver {
  static const commGetValues = 0x09;

  final List<int> _stream = [];
  int _frameNo = 0;
  int _fault = 0;
  ControllerData? _data;
  List<int> _last = const [];

  double _vIn = 0;
  double _iIn = 0;
  double _iMotor = 0;
  double _duty = 0;
  double _erpm = 0;
  double _tempFet = 0;
  double _tempMotor = 0;
  double _ampHours = 0;
  double _wattHours = 0;

  /// 极对数：VESC 上报的是电转速（erpm），轮上转速 = erpm ÷ 极对数
  int polePairs = 20;

  @override
  String get id => 'vesc';
  @override
  String get name => 'VESC（Flipsky / MakerX…）';
  @override
  DriverKind get kind => DriverKind.controller;
  @override
  List<String> get nameHints => const [
        'VESC', 'FLIPSKY', 'MAKERX', 'TRAMPA', 'SPINTEND', 'FSESC', 'FOCER', 'ONEWHEEL',
      ];
  @override
  List<String> get serviceHints => const ['6E400001'];
  @override
  List<String> get notifyHints => const ['6E400003'];
  @override
  List<String> get writeHints => const ['6E400002', 'FFE1'];
  @override
  int get pollIntervalMs => 250;

  @override
  List<List<int>> pollFrames(int tick) => [vescPacket([commGetValues])];

  @override
  void reset() {
    _stream.clear();
    _frameNo = 0;
    _fault = 0;
    _data = null;
    _last = const [];
  }

  @override
  ControllerData? get controllerData => _data;
  @override
  List<int> get lastFrame => _last;
  @override
  String get detail => 'VESC 报文 · $polePairs 极对';

  static int crc16(List<int> data) {
    var crc = 0;
    for (final b in data) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
      }
    }
    return crc & 0xFFFF;
  }

  static List<int> vescPacket(List<int> payload) {
    final crc = crc16(payload);
    return [0x02, payload.length, ...payload, (crc >> 8) & 0xFF, crc & 0xFF, 0x03];
  }

  @override
  bool feed(List<int> chunk) {
    if (chunk.isEmpty) return false;
    _stream.addAll(chunk);
    if (_stream.length > 1024) _stream.removeRange(0, _stream.length - 1024);

    var parsed = false;
    var i = 0;
    while (_stream.length - i >= 5) {
      final b = _stream[i];
      if (b == 0x02) {
        final len = _stream[i + 1];
        final total = len + 5; // 02 len payload crc(2) 03
        if (_stream.length - i < total) break;
        final payload = _stream.sublist(i + 2, i + 2 + len);
        final crc = ((_stream[i + 2 + len] & 0xFF) << 8) | (_stream[i + 3 + len] & 0xFF);
        if (crc16(payload) == crc && _stream[i + 4 + len] == 0x03) {
          if (len > 0 && payload[0] == commGetValues) {
            _last = _stream.sublist(i, i + total);
            if (_parseValues(payload)) parsed = true;
          }
          i += total;
          continue;
        }
      }
      if (b == 0x03) {
        final len = _stream[i + 1];
        final total = len + 5;
        if (_stream.length - i < total) break;
        i += total;
        continue;
      }
      i++;
    }
    if (i > 0) _stream.removeRange(0, i);
    return parsed;
  }

  bool _parseValues(List<int> p) {
    // payload[0] = 0x09，字段从 1 开始，顺序见固件 commands.c
    var o = 1;
    bool need(int n) => p.length >= o + n;

    if (!need(40)) return false;
    _tempFet = i16be(p, o) / 10.0;
    o += 2;
    _tempMotor = i16be(p, o) / 10.0;
    o += 2;
    _iMotor = i32be(p, o) / 100.0;
    o += 4;
    _iIn = i32be(p, o) / 100.0;
    o += 4;
    o += 4; // avg_id
    o += 4; // avg_iq
    _duty = i16be(p, o) / 1000.0;
    o += 2;
    _erpm = i32be(p, o).toDouble();
    o += 4;
    _vIn = i16be(p, o) / 10.0;
    o += 2;
    if (need(4)) {
      _ampHours = i32be(p, o) / 10000.0;
      o += 4;
    }
    if (p.length > o + 4 * 6 + 1) {
      o += 4; // amp_hours_charged
      _wattHours = i32be(p, o) / 10000.0;
      o += 4; // watt_hours_charged
      o += 4; // tachometer
      o += 4; // tachometer_abs
      o += 4; // 走到 fault 字节
      _fault = p[o] & 0xFF;
    }

    _frameNo++;
    _publish();
    return true;
  }

  void _publish() {
    final power = _vIn * _iIn;
    final (pVal, pUnit) = fmtPower(power);
    final rpm = (_erpm.abs() / (polePairs > 0 ? polePairs : 20)).round();
    _data = ControllerData(
      at: DateTime.now(),
      model: 'VESC',
      frameCount: _frameNo,
      primary: [
        Metric('输入电压', _vIn.toStringAsFixed(1), 'V'),
        Metric('输入电流', _iIn.toStringAsFixed(1), 'A',
            tone: _iIn < 0 ? MetricTone.good : MetricTone.normal),
        Metric('功率', pVal, pUnit),
        Metric('转速', '$rpm', 'rpm'),
      ],
      secondary: [
        Metric('MOS 温度', _tempFet.toStringAsFixed(0), '℃',
            tone: _tempFet > 75 ? MetricTone.warn : MetricTone.normal),
        Metric('电机温度', _tempMotor.toStringAsFixed(0), '℃',
            tone: _tempMotor > 100 ? MetricTone.warn : MetricTone.normal),
        Metric('电机电流', _iMotor.toStringAsFixed(1), 'A'),
        Metric('占空比', (_duty * 100).toStringAsFixed(0), '%'),
        Metric('电转速', _erpm.toStringAsFixed(0), 'erpm'),
        Metric('累计电量', _ampHours.toStringAsFixed(2), 'Ah'),
        Metric('累计能耗', _wattHours.toStringAsFixed(1), 'Wh'),
        Metric('故障', _fault == 0 ? '正常' : _faultName(_fault), '',
            tone: _fault == 0 ? MetricTone.good : MetricTone.bad),
      ],
      fault: _fault == 0 ? null : _faultName(_fault),
    );
  }

  String _faultName(int code) {
    const names = {
      1: '过压',
      2: '欠压',
      3: 'DRV 错误',
      4: '相电流过流',
      5: 'MOS 过温',
      6: '电机过温',
      7: '栅极驱动过压',
      8: '栅极驱动欠压',
      9: 'MCU 欠压',
      10: '看门狗复位',
      11: '编码器 SPI',
      12: '编码器幅值过低',
      13: '编码器幅值过高',
      14: 'Flash 损坏',
      15: '电流传感器 1 偏置',
      16: '电流传感器 2 偏置',
      17: '电流传感器 3 偏置',
    };
    return names[code] ?? '故障码 $code';
  }
}
