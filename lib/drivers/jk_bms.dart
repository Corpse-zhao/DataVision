import '../core/models.dart';
import 'driver.dart';

/// 极空（JK / JIKONG）保护板，JK02_32S 布局
///
/// 服务 FFE0，读写都走 FFE1（写 handle 0x03、通知 handle 0x05，同一 UUID 不同句柄）。
/// 流程：发 `0x97` 拿设备信息、发 `0x96` 拿设置，两条都回过之后板子自己开始推 0x02 单体帧。
/// 帧头 `55 AA EB 90`，总长 300 字节，最后一字节是前面所有字节之和的低 8 位。
class JkBmsDriver extends DeviceDriver {
  final List<int> _stream = [];
  int _frameNo = 0;
  int _counter = 0;
  String? _model;
  BmsData? _data;
  List<int> _last = const [];

  @override
  String get id => 'jk';
  @override
  String get name => '极空保护板（JK）';
  @override
  DriverKind get kind => DriverKind.bms;
  @override
  List<String> get nameHints => const ['JK', 'JIKONG', 'JK-B', 'JKBMS'];
  @override
  List<String> get serviceHints => const ['FFE0'];
  @override
  List<String> get notifyHints => const ['FFE1'];
  /// 极空是读写同一个特征，这里三条是不同固件的叫法，按顺序试
  @override
  List<String> get writeHints => const ['FFE1', 'FFE2', 'FFF2'];
  @override
  int get pollIntervalMs => 1000;

  @override
  List<List<int>> get initialFrames => [_command(0x97), _command(0x96)];

  @override
  List<List<int>> pollFrames(int tick) {
    // 板子本来就会自己推；每 5 轮补一次命令，防止流停了没人知道
    if (tick % 5 == 0) return [_command(0x96)];
    return const [];
  }

  List<int> _command(int cmd) {
    final f = List<int>.filled(20, 0);
    f[0] = 0xAA;
    f[1] = 0x55;
    f[2] = 0x90;
    f[3] = 0xEB;
    f[4] = cmd;
    f[5] = 0x00;
    f[16] = _counter & 0xFF;
    _counter++;
    var sum = 0;
    for (var i = 0; i < 19; i++) {
      sum = (sum + f[i]) & 0xFF;
    }
    f[19] = sum;
    return f;
  }

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
  String get detail => '${_model == null ? 'JK02 布局' : 'JK02 · $_model'} · 已收 $_frameNo 帧';

  @override
  bool feed(List<int> chunk) {
    if (chunk.isEmpty) return false;
    _stream.addAll(chunk);
    if (_stream.length > 4096) _stream.removeRange(0, _stream.length - 4096);

    var parsed = false;
    var i = 0;
    while (_stream.length - i >= 300) {
      if (_stream[i] != 0x55 || _stream[i + 1] != 0xAA || _stream[i + 2] != 0xEB || _stream[i + 3] != 0x90) {
        i++;
        continue;
      }
      final frame = _stream.sublist(i, i + 300);
      var sum = 0;
      for (var k = 0; k < 299; k++) {
        sum = (sum + frame[k]) & 0xFF;
      }
      if (sum != frame[299]) {
        i++;
        continue;
      }
      if (frame[4] == 0x02) {
        if (_parseCells(frame)) {
          _last = frame;
          parsed = true;
        }
      } else if (frame[4] == 0x03 && _model == null) {
        _model = _ascii(frame, 6, 16);
      }
      i += 300;
    }
    if (i > 0) _stream.removeRange(0, i);
    return parsed;
  }

  String? _ascii(List<int> f, int start, int len) {
    final bytes = <int>[];
    for (var i = start; i < start + len && i < f.length; i++) {
      if (f[i] == 0) break;
      if (f[i] >= 32 && f[i] < 127) bytes.add(f[i]);
    }
    if (bytes.isEmpty) return null;
    return String.fromCharCodes(bytes);
  }

  bool _parseCells(List<int> f) {
    final mask = u32le(f, 70);
    final cells = <double>[];
    for (var i = 0; i < 32; i++) {
      final v = u16le(f, 6 + i * 2) * 0.001;
      final enabled = (mask >> i) & 1 == 1;
      if (enabled || (v > 0.5 && v < 5.0)) {
        if (v > 0.5 && v < 5.0) cells.add(v);
      }
    }
    if (cells.isEmpty) return false;

    final powerTubeTemp = i16le(f, 144) / 10.0;
    final packV = u32le(f, 150) * 0.001;
    final current = i32le(f, 158) * 0.001; // 正=充电
    final t1 = i16le(f, 162) / 10.0;
    final t2 = i16le(f, 164) / 10.0;
    final errors = u32le(f, 166);
    final balanceCurrent = i16le(f, 170) * 0.001;
    final balanceAction = f[172];
    final soc = f[173];
    final remainingAh = u32le(f, 174) * 0.001;
    final nominalAh = u32le(f, 178) * 0.001;
    final cycles = u32le(f, 182);
    final soh = f[190];
    final chargeMos = f[198] == 1;
    final dischargeMos = f[199] == 1;
    final heating = f[215] == 1;

    var maxV = cells.reduce((a, b) => a > b ? a : b);
    var minV = cells.reduce((a, b) => a < b ? a : b);
    final deltaV = maxV - minV;
    final maxIdx = cells.indexOf(maxV) + 1;
    final minIdx = cells.indexOf(minV) + 1;

    var balancingMask = 0;
    if (balanceAction != 0) {
      for (var i = 0; i < cells.length; i++) {
        balancingMask |= 1 << i;
      }
    }

    final power = packV * current;
    final (pVal, pUnit) = fmtPower(power);
    final flags = _errorNames(errors);

    _frameNo++;
    _data = BmsData(
      at: DateTime.now(),
      brand: '极空',
      model: _model ?? 'JK BMS',
      cells: cells,
      temps: [t1, t2].where((t) => t > -40 && t < 120).toList(),
      maxIdx: maxIdx,
      minIdx: minIdx,
      maxV: maxV,
      minV: minV,
      deltaV: deltaV,
      soc: soc,
      soh: soh,
      chargeMos: chargeMos,
      dischargeMos: dischargeMos,
      balancer: balanceAction != 0,
      balancingMask: balancingMask,
      protection: flags.where((e) => !e.endsWith('告警')).toList(),
      warning: flags.where((e) => e.endsWith('告警')).toList(),
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
        Metric('剩余容量', remainingAh.toStringAsFixed(1), 'Ah'),
        Metric('额定容量', nominalAh.toStringAsFixed(1), 'Ah'),
        Metric('循环', '$cycles', '次'),
        Metric('健康度', '$soh', '%'),
        Metric('功率管温度', powerTubeTemp.toStringAsFixed(0), '℃',
            tone: powerTubeTemp > 65 ? MetricTone.warn : MetricTone.normal),
        Metric('均衡电流', balanceCurrent.toStringAsFixed(2), 'A'),
        Metric('充电 MOS', chargeMos ? '开' : '关', '',
            tone: chargeMos ? MetricTone.good : MetricTone.warn),
        Metric('放电 MOS', dischargeMos ? '开' : '关', '',
            tone: dischargeMos ? MetricTone.good : MetricTone.bad),
        Metric('加热', heating ? '开启' : '关闭', ''),
        Metric('单体数', '${cells.length}', 'S'),
      ],
    );
    return true;
  }

  static const _errorBits = {
    0: '均衡线电阻异常告警',
    1: 'MOS 过温告警',
    2: '单体数量与设置不符告警',
    4: '电池已充满',
    5: '总压过压告警',
    6: '充电过流告警',
    7: '充电短路告警',
    8: '充电高温告警',
    9: '充电低温告警',
    10: '协处理器通讯异常告警',
    11: '单体欠压告警',
    12: '总压欠压告警',
    13: '放电过流告警',
    14: '放电短路告警',
    15: '放电高温告警',
    16: '充电 MOS 异常',
    17: '放电 MOS 异常',
    20: '放电开启失败',
    21: '电池高温',
    22: '温度传感器异常',
    23: 'PL 模块异常',
    24: '短路保护解除失败',
    25: '放电过流 II',
    26: '放电过流 III',
    27: '放电低温告警',
    28: 'GPS 远程锁',
  };

  List<String> _errorNames(int mask) {
    final out = <String>[];
    for (var i = 0; i < 32; i++) {
      if ((mask >> i) & 1 == 1) {
        final n = _errorBits[i];
        if (n != null) out.add(n);
      }
    }
    return out;
  }
}
