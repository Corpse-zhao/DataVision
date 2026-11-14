import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/drivers/registry.dart';

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
}
