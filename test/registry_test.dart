import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/drivers/ant_bms.dart';
import 'package:datavision/drivers/driver.dart';
import 'package:datavision/drivers/lingbo.dart';
import 'package:datavision/drivers/registry.dart';
import 'package:datavision/drivers/vesc.dart';

void main() {
  group('控制器列表要排掉保护板', () {
    test('蚂蚁板的各种写法都认得出', () {
      expect(looksLikeBmsName('ANT-8S24V'), isTrue);
      expect(looksLikeBmsName('ANTBMS'), isTrue);
      expect(looksLikeBmsName('ant-bms-24s'), isTrue);
    });

    test('极空板的各种写法都认得出', () {
      expect(looksLikeBmsName('JK-B2A24S'), isTrue);
      expect(looksLikeBmsName('JKBMS'), isTrue);
      expect(looksLikeBmsName('Jikong-8S'), isTrue);
    });

    test('控制器不能被误杀', () {
      expect(looksLikeBmsName('VOTOL-EM50'), isFalse);
      expect(looksLikeBmsName('FARDRIVER'), isFalse);
      expect(looksLikeBmsName('LBMC'), isFalse);
      expect(looksLikeBmsName('Flipsky VESC'), isFalse);
      expect(looksLikeBmsName('YUANQU'), isFalse);
    });

    test('空名字不算', () {
      expect(looksLikeBmsName(''), isFalse);
      expect(looksLikeBmsName('   '), isFalse);
    });
  });

  group('扫描列表只留认识的设备', () {
    final ctrlPool = controllerDrivers();

    test('名字命中品牌的算认识', () {
      expect(looksKnown(ctrlPool, 'VOTOL-EM50', const []), isTrue);
      expect(looksKnown(ctrlPool, 'FARDRIVER', const []), isTrue);
      expect(looksKnown(ctrlPool, 'Flipsky VESC', const []), isTrue);
    });

    test('只有服务对得上的也算认识（广播名被改过的情况）', () {
      expect(looksKnown(ctrlPool, 'BT05', const ['FFE0']), isTrue);
      expect(looksKnown(ctrlPool, 'NUS-1234', const ['6E400001']), isTrue);
    });

    test('耳机 / 手环 / 无名的都算不认识', () {
      expect(looksKnown(ctrlPool, 'AirPods Pro', const []), isFalse);
      expect(looksKnown(ctrlPool, 'Mi Band 7', const []), isFalse);
      expect(looksKnown(ctrlPool, '未知设备', const []), isFalse);
      expect(looksKnown(ctrlPool, '', const ['180F']), isFalse);
    });
  });

  group('假在线判定按协议给够时间', () {
    test('蚂蚁板 152 字节分多包，阈值要比默认宽', () {
      final ant = AntBmsDriver();
      expect(
        ant.staleTimeoutSeconds,
        greaterThan(DeviceDriver.defaultStaleSeconds),
      );
    });

    test('控制器保持默认，掉线要能马上重连', () {
      expect(
        LingboDriver().staleTimeoutSeconds,
        DeviceDriver.defaultStaleSeconds,
      );
      expect(
        VescDriver().staleTimeoutSeconds,
        DeviceDriver.defaultStaleSeconds,
      );
    });
  });
}
