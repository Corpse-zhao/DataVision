import '../core/models.dart';
import 'driver.dart';

/// 蚂蚁保护板（ANT BMS）
///
/// 帧结构：`7E A1 | 功能码 | 地址(2) | 数据长度(1) | 数据域 | CRC16(2,小端) | AA 55`
/// 总长 = 6 + 数据长度 + 4；CRC16 为 Modbus（poly 0xA001、初值 0xFFFF），
/// 校验范围是帧内 [1 .. len-5]。请求固定 `7E A1 01 00 00 BE 18 55 AA 55`，应答功能码 0x11。
///
/// 信道上蚂蚁板有三种玩法（Data / honeTX / screenTX 之类），所以写入通道要按顺序试：
/// 第一条回数据就锁定它，并记到本地，下次直接用它。
class AntBmsDriver extends DeviceDriver {
  static const statusRequest = [0x7E, 0xA1, 0x01, 0x00, 0x00, 0xBE, 0x18, 0x55, 0xAA, 0x55];

  final List<int> _stream = [];
  int _frameNo = 0;
  BmsData? _data;
  List<int> _last = const [];

  @override
  String get id => 'ant';
  @override
  String get name => '蚂蚁保护板（ANT）';
  @override
  DriverKind get kind => DriverKind.bms;
  @override
  List<String> get nameHints => const ['ANT', 'ANTBMS', 'ANT-BMS'];
  @override
  List<String> get serviceHints => const ['FFE0'];
  @override
  List<String> get notifyHints => const ['FFE1'];
  /// 三条信道依次回退：FFE2（标准写口）→ FFE1（读写合一）→ FFF2（透传模块常见）
  @override
  List<String> get writeHints => const ['FFE2', 'FFE1', 'FFF2', 'FFE3'];
  @override
  int get pollIntervalMs => 400;

  @override
  List<List<int>> pollFrames(int tick) => const [statusRequest];

  @override
  void reset() {
    _stream.clear();
    _frameNo = 0;
    _data = null;
    _last = const [];
  }

  @override
  BmsData? get bmsData => _data;
  @override
  List<int> get lastFrame => _last;
  @override
  String get detail => '应答功能码 0x11 · 已收 $_frameNo 帧';

  static const _protection = {
    0: '单体过压', 1: '单体欠压', 2: '总压过压', 3: '总压欠压', 4: '充电过流', 5: '放电过流',
    6: '短路', 7: '充电器过压', 8: '充电高温', 9: '放电高温', 10: '充电低温', 11: '放电低温',
    12: 'MOS 高温', 13: '环境高温', 14: '环境低温',
  };
  static const _warning = {
    0: '单体过压告警', 1: '单体欠压告警', 2: '总压过压告警', 3: '总压欠压告警',
    4: '充电过流告警', 5: '放电过流告警', 8: '充电高温告警', 9: '放电高温告警',
    10: '充电低温告警', 11: '放电低温告警', 12: '环境高温告警', 13: '环境低温告警',
    14: 'MOS 高温告警', 15: '电量低告警',
  };

  @override
  bool feed(List<int> chunk) {
    if (chunk.isEmpty) return false;
    _stream.addAll(chunk);
    if (_stream.length > 2048) _stream.removeRange(0, _stream.length - 2048);

    var parsed = false;
    var i = 0;
    while (_stream.length - i >= 6) {
      if (_stream[i] != 0x7E || _stream[i + 1] != 0xA1) {
        i++;
        continue;
      }
      final dataLen = _stream[i + 5];
      final frameLen = 6 + dataLen + 4;
      if (frameLen < 12 || frameLen > 512) {
        i++;
        continue;
      }
      if (_stream.length - i < frameLen) break;
      final frame = _stream.sublist(i, i + frameLen);
      final crc = _crc16(frame, 1, frameLen - 5);
      final remote = (frame[frameLen - 4] & 0xFF) | ((frame[frameLen - 3] & 0xFF) << 8);
      if (crc != remote) {
        i++;
        continue;
      }
      if (frame[2] == 0x11) {
        if (_parseStatus(frame)) {
          _last = frame;
          parsed = true;
        }
      }
      i += frameLen;
    }
    if (i > 0) _stream.removeRange(0, i);
    return parsed;
  }

  static int _crc16(List<int> f, int from, int count) {
    var crc = 0xFFFF;
    for (var i = from; i < from + count && i < f.length; i++) {
      crc ^= f[i] & 0xFF;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
    }
    return crc & 0xFFFF;
  }

  int _u16(List<int> f, int i) => (i + 1 < f.length) ? u16le(f, i) : 0;
  int _i16(List<int> f, int i) => (i + 1 < f.length) ? i16le(f, i) : 0;
  int _u32(List<int> f, int i) => (i + 3 < f.length) ? u32le(f, i) : 0;

  bool _parseStatus(List<int> f) {
    if (f.length < 34) return false;
    final status = f[7];
    final tempCount = (f[8] & 0xFF).clamp(0, 8);
    final cellCount = (f[9] & 0xFF).clamp(0, 32);
    if (cellCount <= 0) return false;

    final prot = _bits(f, 10);
    final warn = _bits(f, 18);
    final balance = _bits(f, 26);

    final cells = <double>[];
    for (var i = 0; i < cellCount; i++) {
      final v = _u16(f, 34 + i * 2) * 0.001;
      if (v > 0.5 && v < 5.0) cells.add(v);
    }

    var off = cellCount * 2;
    final temps = <double>[];
    for (var i = 0; i < tempCount; i++) {
      temps.add(_i16(f, 34 + off + i * 2).toDouble());
    }
    off += tempCount * 2;

    final mosTemp = _i16(f, 34 + off).toDouble();
    final balTemp = _i16(f, 36 + off).toDouble();
    final packV = _u16(f, 38 + off) * 0.01;
    final current = _i16(f, 40 + off) * 0.1; // 正=充电
    final soc = _u16(f, 42 + off).clamp(0, 100);
    final soh = _u16(f, 44 + off).clamp(0, 100);

    var chargeMos = false, dischargeMos = false, balancerOn = false;
    if (f.length > 48 + off) {
      chargeMos = f[46 + off] == 0x01;
      dischargeMos = f[47 + off] == 0x01;
      balancerOn = f[48 + off] == 0x04;
    }

    double capacityAh = 0, remainingAh = 0, cycles = 0;
    if (f.length >= 54 + off) {
      capacityAh = _u32(f, 50 + off) * 0.000001;
      remainingAh = _u32(f, 54 + off) * 0.000001;
      cycles = _u32(f, 58 + off) * 0.001;
    }

    var maxV = 0.0, minV = 0.0, deltaV = 0.0, avgV = 0.0;
    var maxIdx = 0, minIdx = 0;
    if (f.length >= 86 + off) {
      maxV = _u16(f, 74 + off) * 0.001;
      maxIdx = _u16(f, 76 + off);
      minV = _u16(f, 78 + off) * 0.001;
      minIdx = _u16(f, 80 + off);
      deltaV = _u16(f, 82 + off) * 0.001;
      avgV = _u16(f, 84 + off) * 0.001;
    }
    if (cells.isNotEmpty) {
      final mx = cells.reduce((a, b) => a > b ? a : b);
      final mn = cells.reduce((a, b) => a < b ? a : b);
      if (maxV <= 0) maxV = mx;
      if (minV <= 0) minV = mn;
      if (deltaV <= 0) deltaV = mx - mn;
      if (avgV <= 0) avgV = cells.reduce((a, b) => a + b) / cells.length;
      if (maxIdx == 0) maxIdx = cells.indexOf(mx) + 1;
      if (minIdx == 0) minIdx = cells.indexOf(mn) + 1;
    }

    final power = packV * current;
    final (pVal, pUnit) = fmtPower(power);
    final protNames = _names(prot, _protection);
    final warnNames = _names(warn, _warning);

    _frameNo++;
    _data = BmsData(
      at: DateTime.now(),
      brand: '蚂蚁',
      model: 'ANT BMS',
      cells: cells,
      temps: temps,
      maxIdx: maxIdx,
      minIdx: minIdx,
      maxV: maxV,
      minV: minV,
      deltaV: deltaV,
      soc: soc,
      soh: soh,
      chargeMos: chargeMos,
      dischargeMos: dischargeMos,
      balancer: balancerOn,
      balancingMask: balance,
      protection: protNames,
      warning: warnNames,
      primary: [
        Metric('总电压', packV.toStringAsFixed(2), 'V'),
        Metric('电流', current.toStringAsFixed(1), 'A',
            tone: current < 0 ? MetricTone.warn : MetricTone.good),
        Metric('电量', '$soc', '%', tone: soc < 20 ? MetricTone.warn : MetricTone.good),
        Metric('功率', pVal, pUnit),
      ],
      secondary: [
        Metric('压差', (deltaV * 1000).toStringAsFixed(0), 'mV',
            tone: deltaV > 0.05 ? MetricTone.warn : MetricTone.good),
        Metric('最高单体', '${maxV.toStringAsFixed(3)}V #$maxIdx', ''),
        Metric('最低单体', '${minV.toStringAsFixed(3)}V #$minIdx', ''),
        Metric('平均单体', avgV.toStringAsFixed(3), 'V'),
        Metric('剩余容量', remainingAh.toStringAsFixed(1), 'Ah'),
        Metric('额定容量', capacityAh.toStringAsFixed(1), 'Ah'),
        Metric('循环', cycles.toStringAsFixed(0), '次'),
        Metric('健康度', '$soh', '%'),
        Metric('MOS 温度', mosTemp.toStringAsFixed(0), '℃',
            tone: mosTemp > 60 ? MetricTone.warn : MetricTone.normal),
        Metric('均衡温度', balTemp.toStringAsFixed(0), '℃'),
        Metric('充电 MOS', chargeMos ? '开' : '关', '',
            tone: chargeMos ? MetricTone.good : MetricTone.warn),
        Metric('放电 MOS', dischargeMos ? '开' : '关', '',
            tone: dischargeMos ? MetricTone.good : MetricTone.bad),
        Metric('均衡', balancerOn ? '工作中' : '待机', '',
            tone: balancerOn ? MetricTone.good : MetricTone.normal),
        Metric('状态', _statusName(status), ''),
        Metric('单体数', '${cells.length}', 'S'),
      ],
    );
    return true;
  }

  int _bits(List<int> f, int start) {
    if (start + 7 >= f.length) return 0;
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v |= (f[start + i] & 0xFF) << (8 * i);
    }
    return v;
  }

  List<String> _names(int mask, Map<int, String> table) {
    final out = <String>[];
    if (mask == 0) return out;
    for (var i = 0; i < 64; i++) {
      if ((mask >> i) & 1 == 1) {
        final n = table[i];
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  String _statusName(int s) {
    switch (s) {
      case 1:
        return '静置';
      case 2:
        return '充电中';
      case 3:
        return '放电中';
      case 4:
        return '待机';
      case 5:
        return '故障';
      default:
        return '未知';
    }
  }
}
