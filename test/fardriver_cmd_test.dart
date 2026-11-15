import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/drivers/fardriver.dart';

/// 远驱的「开麦」命令。
///
/// 现场踩过：以为它连上就自己推，结果只订阅通知口时一个字节都收不到。
/// 这些帧一旦写错（校验、命令码、地址索引），表现就是永远「已连上，还没收到数据」，
/// 而且没有任何报错 —— 只能靠这里钉住字节。
void main() {
  group('8 字节命令帧', () {
    test('结构：AA cmd ~cmd sub v1 v2 crc ~crc', () {
      final f = FardriverDriver.command(0x07);
      expect(f.length, 8);
      expect(f[0], 0xAA);
      expect(f[1], 0x07);
      expect(f[2], 0xF8); // ~0x07
      expect(f[3], 0);
      expect(f[4], 0);
      expect(f[5], 0);
    });

    test('校验是前 6 字节求和，末位取反', () {
      final f = FardriverDriver.command(0x07);
      final crc = f.take(6).reduce((a, b) => a + b) & 0xFF;
      expect(f[6], crc);
      expect(f[7], (~crc) & 0xFF);
      // 手算一遍：AA+07+F8+00+00+00 = 0x1A9 → 0xA9
      expect(f[6], 0xA9);
      expect(f[7], 0x56);
    });

    test('带参数时校验跟着变（不能用固定值）', () {
      final a = FardriverDriver.command(0x13, sub: 0x07);
      final b = FardriverDriver.command(0x13, sub: 0x08);
      expect(a[6], isNot(b[6]));
    });
  });

  group('系统命令帧（16 字节，写 0xA0）', () {
    test('id 落在 0xA0 上，长度 16', () {
      final f = FardriverDriver.systemWrite(0x88, 0x06);
      expect(f.length, 16);
      expect(f[0], 0xAA);
      expect(f[1] & 0x3F, 33); // _addressTable[33] == 0xA0
      expect(f[2], 0x88);
      expect(f[3], 0x06);
    });

    test('这个帧喂给驱动不会当成数据（地址不是那四个有用的）', () {
      final d = FardriverDriver();
      expect(d.feed(FardriverDriver.systemWrite(0x88, 0x06)), isFalse);
      expect(d.controllerData, isNull);
    });
  });

  group('发送时机', () {
    test('连上先喊一遍，三条候选命令', () {
      final d = FardriverDriver();
      expect(d.initialFrames.length, 3);
      expect(d.initialFrames.first[1], 0x07);
      expect(d.initialFrames[1][1], 0x06);
      expect(d.initialFrames[2].length, 16);
    });

    test('不是被动型：要发请求才会吐数据', () {
      expect(FardriverDriver().passive, isFalse);
    });

    test('上报有时效，隔几秒补一条，不能每 300ms 刷屏', () {
      final d = FardriverDriver();
      expect(d.pollFrames(1), isEmpty);
      expect(d.pollFrames(12), isEmpty);
      expect(d.pollFrames(13).single[1], 0x07);
      expect(d.pollFrames(26).single[1], 0x07);
    });

    test('掉线判定放宽到 10 秒（上报是一阵一阵的）', () {
      expect(FardriverDriver().staleTimeoutSeconds, greaterThanOrEqualTo(10));
    });
  });

  group('16 字节状态帧解析仍然正常', () {
    List<int> statusFrame(int id, List<int> data) {
      final f = List<int>.filled(16, 0);
      f[0] = 0xAA;
      f[1] = id | 0x80; // flags = 2
      for (var i = 0; i < 12; i++) {
        f[2 + i] = data[i];
      }
      // 用驱动同款 CRC（poly 0xA001、初值 0x7F3C、范围前 14 字节）
      var crc = 0x7F3C;
      for (var i = 0; i < 14; i++) {
        crc ^= f[i] & 0xFF;
        for (var k = 0; k < 8; k++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
        }
      }
      f[14] = crc & 0xFF;
      f[15] = (crc >> 8) & 0xFF;
      return f;
    }

    test('电压电流帧（id 1 → 0xE8）能解析出来', () {
      final d = FardriverDriver();
      final data = List<int>.filled(12, 0);
      data[0] = 0x70; // 0x0370 = 880 → 88.0V
      data[1] = 0x03;
      data[4] = 0x50; // 0x0050 = 80 → 20.0A
      data[5] = 0x00;
      expect(d.feed(statusFrame(1, data)), isTrue);
      expect(d.controllerData!.primary[0].value, '88.0');
      expect(d.controllerData!.primary[1].value, '20.0');
    });
  });
}
