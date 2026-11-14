import '../core/models.dart';
import 'driver.dart';

/// 南京远驱（Fardriver / VOTOL / YuanQuFOC）控制器协议
///
/// **不用发请求**，模块连上就自己往通知通道推。固定 16 字节帧：
/// `AA | id(低6位)+flags(高2位) | 12 字节数据 | CRC16(低 高)`
/// CRC16：poly 0xA001、初值 0x7F3C、范围前 14 字节（和 Modbus 同族但初值不同，
/// 所以凌博那套 0xFFFF 在这里一律不过——首帧嗅探能安全区分两者）。
///
/// id 查表得 flash 地址，真正有用的只有四个：
///   0xE2 转速/挡位、0xE8 电压/电流、0xD6 控制器温度、0xF4 电机温度+SOC
class FardriverDriver extends DeviceDriver {
  static const _addressTable = <int>[
    0xE2, 0xE8, 0xEE, 0xE4, 0x06, 0x0C, 0x12, 0xE2, 0xE8, 0xEE, 0x18, 0x1E, 0x24, 0x2A,
    0xE2, 0xE8, 0xEE, 0x30, 0x5D, 0x63, 0x69, 0xE2, 0xE8, 0xEE, 0x7C, 0x82, 0x88, 0x8E,
    0xE2, 0xE8, 0xEE, 0x94, 0x9A, 0xA0, 0xA6, 0xE2, 0xE8, 0xEE, 0xAC, 0xB2, 0xB8, 0xBE,
    0xE2, 0xE8, 0xEE, 0xC4, 0xCA, 0xD0, 0xE2, 0xE8, 0xEE, 0xD6, 0xDC, 0xF4, 0xFA,
  ];
  static const _crcSeed = 0x7F3C;

  final List<int> _stream = [];

  double _volts = 0;
  double _amps = 0;
  int _rawRpm = 0;
  int _gear = 0;
  int _ctrlTemp = 0;
  int _motorTemp = 0;
  int _soc = 0;
  bool _got = false;
  int _frameNo = 0;
  ControllerData? _data;
  List<int> _last = const [];

  /// 极对数：远驱上报的是电机机械转速×4，换算成轮上转速要除极对数
  int polePairs = 20;

  @override
  String get id => 'fardriver';
  @override
  String get name => '远驱 Fardriver / VOTOL';
  @override
  DriverKind get kind => DriverKind.controller;
  @override
  List<String> get nameHints => const ['VOTOL', 'FARDRIVER', 'YUANQU'];
  @override
  List<String> get serviceHints => const ['FFE0', 'FFF0'];
  @override
  List<String> get notifyHints => const ['FFEC'];
  @override
  List<String> get writeHints => const [];
  @override
  bool get passive => true;
  @override
  int get pollIntervalMs => 300;

  @override
  void reset() {
    _stream.clear();
    _volts = 0;
    _amps = 0;
    _rawRpm = 0;
    _gear = 0;
    _ctrlTemp = 0;
    _motorTemp = 0;
    _soc = 0;
    _got = false;
    _frameNo = 0;
    _data = null;
    _last = const [];
  }

  @override
  ControllerData? get controllerData => _data;
  @override
  List<int> get lastFrame => _last;
  @override
  String get detail => _got ? '直读，无需标定 · $polePairs 极对' : '等首帧';

  @override
  bool feed(List<int> chunk) {
    if (chunk.isEmpty) return false;
    _stream.addAll(chunk);
    if (_stream.length > 256) _stream.removeRange(0, _stream.length - 256);

    var parsed = false;
    // 16 字节定长，靠 CRC 对齐起点
    var i = 0;
    while (_stream.length - i >= 16) {
      if (_stream[i] != 0xAA) {
        i++;
        continue;
      }
      final frame = _stream.sublist(i, i + 16);
      final addr = _addressOf(frame);
      if (addr == null) {
        i++;
        continue;
      }
      if (_applyFrame(frame, addr)) {
        _last = frame;
        parsed = true;
      }
      i += 16;
    }
    if (i > 0) _stream.removeRange(0, i);

    if (parsed) _publish();
    return parsed;
  }

  static int? _addressOf(List<int> f) {
    final id = f[1] & 0x3F;
    if (id >= _addressTable.length) return null;
    final computed = _crc16(f);
    final remote = (f[15] << 8) | f[14];
    if (computed != remote) return null;
    return _addressTable[id];
  }

  static int _crc16(List<int> frame) {
    var crc = _crcSeed;
    for (var i = 0; i < 14; i++) {
      crc ^= frame[i] & 0xFF;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
    }
    return crc & 0xFFFF;
  }

  bool _applyFrame(List<int> f, int addr) {
    final d = f.sublist(2, 14);
    switch (addr) {
      case 0xE2:
        _gear = ((d[0] >> 2) & 0x03) + 1;
        _rawRpm = i16le(d, 6);
        break;
      case 0xE8:
        final v = u16le(d, 0) / 10.0;
        if (v >= 0 && v <= 100) _volts = v;
        final a = i16le(d, 4) / 4.0;
        if (a >= -100 && a <= 300) _amps = a;
        break;
      case 0xD6:
        final t = i16le(d, 10);
        if (t > -20 && t < 100) _ctrlTemp = t;
        break;
      case 0xF4:
        final t = i16le(d, 0);
        if (t > -20 && t < 200) _motorTemp = t;
        _soc = d[3] & 0xFF;
        break;
      default:
        return false;
    }
    _got = true;
    _frameNo++;
    return true;
  }

  void _publish() {
    final rpm = (_rawRpm.abs() * 4) ~/ (polePairs > 0 ? polePairs : 20);
    final power = _volts * _amps;
    final (pVal, pUnit) = fmtPower(power);
    _data = ControllerData(
      at: DateTime.now(),
      model: '远驱',
      frameCount: _frameNo,
      primary: [
        Metric('母线电压', _volts.toStringAsFixed(1), 'V'),
        Metric('母线电流', _amps.toStringAsFixed(1), 'A',
            tone: _amps < 0 ? MetricTone.good : MetricTone.normal),
        Metric('功率', pVal, pUnit),
        Metric('转速', '$rpm', 'rpm'),
      ],
      secondary: [
        Metric('控制器温度', '$_ctrlTemp', '℃',
            tone: _ctrlTemp > 80 ? MetricTone.warn : MetricTone.normal),
        Metric('电机温度', '$_motorTemp', '℃',
            tone: _motorTemp > 100 ? MetricTone.warn : MetricTone.normal),
        Metric('挡位', _gear > 0 ? '$_gear' : '--', ''),
        Metric('电量(SOC)', _soc > 0 && _soc <= 100 ? '$_soc' : '--', '%'),
        Metric('电机转速', '${_rawRpm.abs() * 4}', 'rpm'),
        Metric('极对数', '$polePairs', ''),
      ],
    );
  }
}
