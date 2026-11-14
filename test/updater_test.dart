import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/core/updater.dart';

void main() {
  group('版本号归一化', () {
    test('去掉前缀字母', () {
      expect(normalizeVersion('v1.0.5'), '1.0.5');
      expect(normalizeVersion('V1.0.5'), '1.0.5');
      expect(normalizeVersion('release-1.0.10'), '1.0.10');
      expect(normalizeVersion('1.0.4'), '1.0.4');
    });

    test('没有数字就是空', () {
      expect(normalizeVersion('latest'), '');
      expect(normalizeVersion(''), '');
    });
  });

  group('版本比较', () {
    test('基本大小', () {
      expect(compareVersions('1.0.5', '1.0.4'), 1);
      expect(compareVersions('1.0.4', '1.0.4'), 0);
      expect(compareVersions('1.0.3', '1.0.4'), -1);
    });

    test('按数字段比，不是按字符串比', () {
      expect(compareVersions('1.10.0', '1.9.9'), 1);
      expect(compareVersions('1.0.10', '1.0.9'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('缺的位按 0 算', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.1', '1.0.9'), 1);
    });

    test('带 v 前缀也能比', () {
      expect(compareVersions('v1.0.5', '1.0.4'), 1);
      expect(compareVersions('v1.0.4', '1.0.4'), 0);
    });
  });

  group('下载地址', () {
    test('原始地址在最前，镜像跟在后面', () {
      const raw = 'https://github.com/Corpse-zhao/DataVision/releases/download/v1.0.5/DataVision-v1.0.5.apk';
      final urls = Updater.candidateUrls(raw);
      expect(urls.first, raw);
      expect(urls.length, greaterThanOrEqualTo(2));
      for (final u in urls.skip(1)) {
        expect(u.endsWith(raw), isTrue);
        expect(u.startsWith('https://'), isTrue);
      }
    });
  });

  group('大小格式化', () {
    test('MB / KB / 空', () {
      expect(humanSize(51235328), '48.9 MB');
      expect(humanSize(6942996), '6.6 MB');
      expect(humanSize(2048), '2 KB');
      expect(humanSize(0), '');
    });
  });
}
