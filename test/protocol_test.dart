import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/drivers/ant_bms.dart';
import 'package:datavision/drivers/fardriver.dart';
import 'package:datavision/drivers/jk_bms.dart';
import 'package:datavision/drivers/lingbo.dart';
import 'package:datavision/drivers/vesc.dart';

// ---------------------------------------------------------------------------
// 造帧工具：按协议把字段写进真实帧结构，再喂给驱动。
// 解析器对偏移写错一个字节，这里的断言就会挂——没有真机时这是唯一能验证的办法。
// ---------------------------------------------------------------------------

int _sum8(List<int> bytes) => bytes.fold<int>(0, (a, b) => (a + b) & 0xFF);

void _put16le(List<int> b, int o, int v) {
  b[o] = v & 0xFF;
  b[o + 1] = (v >> 8) & 0xFF;
}

void _putS16le(List<int> b, int o, int v) => _put16le(b, o, v & 0xFFFF);

void _put32le(List<int> b, int o, int v) {
  b[o] = v & 0xFF;
  b[o + 1] = (v >> 8) & 0xFF;
  b[o + 2] = (v >> 16) & 0xFF;
  b[o + 3] = (v >> 24) & 0xFF;
}

/// 凌博标定帧 0x60（16 字节）
List<int> lingboCalibration({int divI = 100, int divV = 63}) {
  final f = List<int>.filled(16, 0);
  f[0] = 0xAA;
  f[1] = 0x55;
  f[2] = 0x0D; // 总长 = LEN + 3 = 16
  f[3] = 0x60;
  _put16le(f, 4, 500); // 相电流基准
  _put16le(f, 6, 300); // 相电压基准
  _put16le(f, 8, divI);
  _put16le(f, 10, divV);
  f[12] = 0; // 控制模式
  _put16le(f, 13, 800); // 扭矩上限
  f[15] = _sum8(f.sublist(0, 15));
  return f;
}

/// 凌博实时帧 0x62（29 字节）
List<int> lingboRealtime({
  int rpm = 1000,
  int rawVolts = 3800,
  int rawAmps = 2000,
  int ctrlTemp = 45,
  int motorTemp = 50,
  int throttleRaw = 250,
  int gear = 2,
  int fault = 0,
}) {
  final f = List<int>.filled(29, 0);
  f[0] = 0xAA;
  f[1] = 0x55;
  f[2] = 0x1A;
  f[3] = 0x62;
  _putS16le(f, 4, rpm);
  _put16le(f, 6, 100); // 相电流²
  _put16le(f, 10, rawVolts);
  _putS16le(f, 12, rawAmps);
  _putS16le(f, 14, ctrlTemp);
  _putS16le(f, 16, motorTemp);
  _put32le(f, 18, fault);
  _put16le(f, 22, throttleRaw);
  f[24] = 0x03;
  f[27] = gear & 0x0F;
  f[28] = _sum8(f.sublist(0, 28));
  return f;
}

int _fardriverCrc(List<int> f) {
  var crc = 0x7F3C;
  for (var i = 0; i < 14; i++) {
    crc ^= f[i] & 0xFF;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc & 0xFFFF;
}

/// 远驱 16 字节帧：id 查表得地址，这里按地址反查一个可用 id
List<int> fardriverFrame(int address, void Function(List<int> data) fill) {
  const table = <int>[
    0xE2,
    0xE8,
    0xEE,
    0xE4,
    0x06,
    0x0C,
    0x12,
    0xE2,
    0xE8,
    0xEE,
    0x18,
    0x1E,
    0x24,
    0x2A,
    0xE2,
    0xE8,
    0xEE,
    0x30,
    0x5D,
    0x63,
    0x69,
    0xE2,
    0xE8,
    0xEE,
    0x7C,
    0x82,
    0x88,
    0x8E,
    0xE2,
    0xE8,
    0xEE,
    0x94,
    0x9A,
    0xA0,
    0xA6,
    0xE2,
    0xE8,
    0xEE,
    0xAC,
    0xB2,
    0xB8,
    0xBE,
    0xE2,
    0xE8,
    0xEE,
    0xC4,
    0xCA,
    0xD0,
    0xE2,
    0xE8,
    0xEE,
    0xD6,
    0xDC,
    0xF4,
    0xFA,
  ];
  final id = table.indexOf(address);
  final f = List<int>.filled(16, 0);
  f[0] = 0xAA;
  f[1] = id & 0x3F;
  final data = List<int>.filled(12, 0);
  fill(data);
  for (var i = 0; i < 12; i++) {
    f[2 + i] = data[i];
  }
  final crc = _fardriverCrc(f);
  f[14] = crc & 0xFF;
  f[15] = (crc >> 8) & 0xFF;
  return f;
}

int _crcModbus(List<int> f, int from, int count) {
  var crc = 0xFFFF;
  for (var i = from; i < from + count; i++) {
    crc ^= f[i] & 0xFF;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc & 0xFFFF;
}

/// 蚂蚁保护板状态帧（功能码 0x11）
List<int> antStatusFrame({
  int cells = 20,
  int temps = 4,
  double cellV = 3.65,
  double packV = 73.0,
  double amps = 12.3,
  int soc = 78,
  int soh = 99,
}) {
  final dataLen = 160;
  final total = 6 + dataLen + 4;
  final f = List<int>.filled(total, 0);
  f[0] = 0x7E;
  f[1] = 0xA1;
  f[2] = 0x11;
  f[3] = 0x00;
  f[4] = 0x00;
  f[5] = dataLen;
  f[7] = 3; // 放电中
  f[8] = temps;
  f[9] = cells;

  for (var i = 0; i < cells; i++) {
    _put16le(f, 34 + i * 2, (cellV * 1000).round());
  }
  var off = cells * 2;
  for (var i = 0; i < temps; i++) {
    _putS16le(f, 34 + off + i * 2, 25 + i);
  }
  off += temps * 2;

  _putS16le(f, 34 + off, 32); // MOS 温度
  _putS16le(f, 36 + off, 28); // 均衡温度
  _put16le(f, 38 + off, (packV * 100).round()); // 总电压
  _putS16le(f, 40 + off, (amps * 10).round()); // 电流（正=充电）
  _put16le(f, 42 + off, soc);
  _put16le(f, 44 + off, soh);
  f[46 + off] = 0x01; // 充电 MOS 开
  f[47 + off] = 0x01; // 放电 MOS 开
  f[48 + off] = 0x00; // 均衡关

  _put32le(f, 50 + off, 50000000); // 额定容量 50Ah（×1e-6）
  _put32le(f, 54 + off, 39000000); // 剩余 39Ah
  _put32le(f, 58 + off, 120000); // 循环 120
  _put16le(f, 74 + off, (cellV * 1000).round() + 20); // 最高单体
  _put16le(f, 76 + off, 1);
  _put16le(f, 78 + off, (cellV * 1000).round() - 20); // 最低单体
  _put16le(f, 80 + off, cells);
  _put16le(f, 82 + off, 40); // 压差 0.040V
  _put16le(f, 84 + off, (cellV * 1000).round());

  final crc = _crcModbus(f, 1, total - 5);
  f[total - 4] = crc & 0xFF;
  f[total - 3] = (crc >> 8) & 0xFF;
  f[total - 2] = 0xAA;
  f[total - 1] = 0x55;
  return f;
}

/// 极空单体信息帧（JK02_32S，300 字节）
List<int> jkCellFrame({
  int cells = 16,
  double cellV = 3.30,
  double packV = 52.8,
  double amps = -15.5, // 负 = 放电
  int soc = 64,
}) {
  final f = List<int>.filled(300, 0);
  f[0] = 0x55;
  f[1] = 0xAA;
  f[2] = 0xEB;
  f[3] = 0x90;
  f[4] = 0x02;

  var mask = 0;
  for (var i = 0; i < cells; i++) {
    _put16le(f, 6 + i * 2, (cellV * 1000).round() + i);
    mask |= 1 << i;
  }
  _put32le(f, 70, mask);
  _put16le(f, 74, (cellV * 1000).round());
  _put16le(f, 76, 3);
  f[78] = 1;
  f[79] = 2;
  _putS16le(f, 144, 285); // 功率管 28.5℃
  _put32le(f, 150, (packV * 1000).round());
  _put32le(f, 154, 0);
  _put32le(f, 158, (amps * 1000).round() & 0xFFFFFFFF);
  _putS16le(f, 162, 261); // 26.1℃
  _putS16le(f, 164, 270);
  _put32le(f, 166, 0); // 无告警
  _putS16le(f, 170, 0);
  f[172] = 0;
  f[173] = soc;
  _put32le(f, 174, 16000); // 剩余 16Ah
  _put32le(f, 178, 25000); // 额定 25Ah
  _put32le(f, 182, 88); // 循环
  f[190] = 96; // SOH
  f[198] = 1;
  f[199] = 1;

  var sum = 0;
  for (var i = 0; i < 299; i++) {
    sum = (sum + f[i]) & 0xFF;
  }
  f[299] = sum;
  return f;
}

/// VESC COMM_GET_VALUES 报文
List<int> vescValues({
  double vIn = 66.4,
  double iIn = 18.5,
  double iMotor = 22.0,
  double duty = 0.42,
  int erpm = 12000,
  double tempFet = 41.2,
  double tempMotor = 38.5,
  int fault = 0,
}) {
  final p = <int>[0x09];
  void addS16(double v, double scale) {
    final raw = (v * scale).round() & 0xFFFF;
    p.add((raw >> 8) & 0xFF);
    p.add(raw & 0xFF);
  }

  void addS32(int raw) {
    final v = raw & 0xFFFFFFFF;
    p.add((v >> 24) & 0xFF);
    p.add((v >> 16) & 0xFF);
    p.add((v >> 8) & 0xFF);
    p.add(v & 0xFF);
  }

  addS16(tempFet, 10);
  addS16(tempMotor, 10);
  addS32((iMotor * 100).round());
  addS32((iIn * 100).round());
  addS32(0); // id
  addS32(0); // iq
  addS16(duty, 1000);
  addS32(erpm);
  addS16(vIn, 10);
  addS32((5.2 * 10000).round()); // Ah
  addS32(0); // Ah charged
  addS32((344.5 * 10000).round()); // Wh
  addS32(0);
  addS32(1000); // tach
  addS32(1000); // tach abs
  p.add(fault); // fault code
  addS32(0); // pid pos
  p.add(0); // controller id

  final crc = VescDriver.crc16(p);
  return [0x02, p.length, ...p, (crc >> 8) & 0xFF, crc & 0xFF, 0x03];
}

void main() {
  group('凌博 LBMC', () {
    test('标定帧拿到分母后，实时帧换算正确', () {
      final d = LingboDriver();
      expect(d.feed(lingboCalibration(divI: 63, divV: 63)), isFalse);
      expect(
        d.feed(lingboRealtime(rawVolts: 3800, rawAmps: 1260, rpm: 1200)),
        isTrue,
      );

      final data = d.controllerData!;
      // 3800 / 63 = 60.3V ；1260 / 63 = 20A
      expect(data.primary[0].value, '60.3');
      expect(data.primary[0].unit, 'V');
      expect(data.primary[1].value, '20.0');
      expect(data.primary[3].value, '1200');
      // 转把 2.50V → (2.50-0.85)/(4.2-0.85) = 49%
      expect(data.secondary.firstWhere((m) => m.label == '转把').value, '49');
      expect(data.secondary.firstWhere((m) => m.label == '挡位').value, '2');
      expect(data.fault, isNull);
    });

    test('半截帧不会误判，拼起来才解析', () {
      final d = LingboDriver();
      d.feed(lingboCalibration());
      final frame = lingboRealtime();
      expect(d.feed(frame.sublist(0, 10)), isFalse);
      expect(d.feed(frame.sublist(10)), isTrue);
    });

    test('校验和错的帧要丢掉', () {
      final d = LingboDriver();
      d.feed(lingboCalibration());
      final bad = lingboRealtime();
      bad[28] = (bad[28] + 1) & 0xFF;
      expect(d.feed(bad), isFalse);
    });
  });

  group('远驱 Fardriver', () {
    test('电压/电流帧', () {
      final d = FardriverDriver();
      // 0xE8：电压 u16/10，电流 i16/4
      final f = fardriverFrame(0xE8, (data) {
        _put16le(data, 0, 724); // 72.4V
        _putS16le(data, 4, 88 * 4); // 88A
      });
      expect(d.feed(f), isTrue);
      final data = d.controllerData!;
      expect(data.primary[0].value, '72.4');
      expect(data.primary[1].value, '88.0');
    });

    test('转速按极对数换算 + 温度/SOC', () {
      final d = FardriverDriver()..polePairs = 20;
      d.feed(
        fardriverFrame(0xE2, (data) {
          data[0] = 2 << 2; // 挡位 3
          _putS16le(data, 6, 5000); // 电机 5000rpm
        }),
      );
      d.feed(fardriverFrame(0xD6, (data) => _putS16le(data, 10, 55)));
      d.feed(
        fardriverFrame(0xF4, (data) {
          _putS16le(data, 0, 62);
          data[3] = 77;
        }),
      );

      final data = d.controllerData!;
      // 5000 * 4 / 20 = 1000
      expect(data.primary[3].value, '1000');
      expect(data.secondary.firstWhere((m) => m.label == '控制器温度').value, '55');
      expect(data.secondary.firstWhere((m) => m.label == '电机温度').value, '62');
      expect(
        data.secondary.firstWhere((m) => m.label == '电量(SOC)').value,
        '77',
      );
      expect(data.secondary.firstWhere((m) => m.label == '挡位').value, '3');
    });

    test('CRC 不对不认', () {
      final d = FardriverDriver();
      final f = fardriverFrame(0xE8, (data) => _put16le(data, 0, 700));
      f[15] = (f[15] + 1) & 0xFF;
      expect(d.feed(f), isFalse);
    });
  });

  group('VESC', () {
    test('COMM_GET_VALUES 字段顺序', () {
      final d = VescDriver()..polePairs = 20;
      expect(d.feed(vescValues()), isTrue);
      final data = d.controllerData!;
      expect(data.primary[0].value, '66.4'); // 输入电压
      expect(data.primary[1].value, '18.5'); // 输入电流
      expect(data.primary[3].value, '600'); // 12000 erpm / 20
      expect(data.secondary.firstWhere((m) => m.label == 'MOS 温度').value, '41');
      expect(data.secondary.firstWhere((m) => m.label == '占空比').value, '42');
      expect(data.secondary.firstWhere((m) => m.label == '故障').value, '正常');
    });

    test('故障码翻译', () {
      final d = VescDriver();
      d.feed(vescValues(fault: 5));
      expect(d.controllerData!.fault, 'MOS 过温');
    });

    test('报文被拆成多段也能拼回来', () {
      final d = VescDriver();
      final frame = vescValues();
      expect(d.feed(frame.sublist(0, 7)), isFalse);
      expect(d.feed(frame.sublist(7)), isTrue);
    });
  });

  group('蚂蚁保护板', () {
    test('单体 / 总压 / 电流 / SOC', () {
      final d = AntBmsDriver();
      expect(d.feed(antStatusFrame()), isTrue);
      final data = d.bmsData!;
      expect(data.cells.length, 20);
      expect(data.cells.first.toStringAsFixed(2), '3.65');
      expect(data.primary[0].value, '73.00'); // 总电压
      expect(data.primary[1].value, '12.3'); // 电流
      expect(data.primary[2].value, '78'); // SOC
      expect(data.soc, 78);
      expect(data.soh, 99);
      expect(data.chargeMos, isTrue);
      expect(data.dischargeMos, isTrue);
      expect(data.deltaV.toStringAsFixed(3), '0.040');
      expect(data.secondary.firstWhere((m) => m.label == '剩余容量').value, '39.0');
      expect(data.secondary.firstWhere((m) => m.label == '循环').value, '120');
    });

    test('CRC 错帧丢弃', () {
      final d = AntBmsDriver();
      final f = antStatusFrame();
      f[f.length - 4] = (f[f.length - 4] + 1) & 0xFF;
      expect(d.feed(f), isFalse);
    });
  });

  group('极空保护板', () {
    test('JK02_32S 偏移', () {
      final d = JkBmsDriver();
      expect(d.feed(jkCellFrame()), isTrue);
      final data = d.bmsData!;
      expect(data.cells.length, 16);
      expect(data.primary[0].value, '52.80'); // 总电压
      expect(data.primary[1].value, '-15.5'); // 放电为负
      expect(data.soc, 64);
      expect(data.soh, 96);
      expect(data.secondary.firstWhere((m) => m.label == '剩余容量').value, '16.0');
      expect(data.secondary.firstWhere((m) => m.label == '额定容量').value, '25.0');
      expect(data.secondary.firstWhere((m) => m.label == '循环').value, '88');
      expect(data.chargeMos, isTrue);
      expect(data.dischargeMos, isTrue);
      // 压差 = 最高 3.315 - 最低 3.300
      expect((data.deltaV * 1000).toStringAsFixed(0), '15');
    });

    test('尾字节校验错就丢', () {
      final d = JkBmsDriver();
      final f = jkCellFrame();
      f[299] = (f[299] + 1) & 0xFF;
      expect(d.feed(f), isFalse);
    });
  });

  test('Uint8List 输入也能喂（蓝牙给的就是这个类型）', () {
    final d = VescDriver();
    final frame = Uint8List.fromList(vescValues());
    expect(d.feed(frame), isTrue);
  });
}
