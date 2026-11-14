import 'dart:convert';
import 'dart:io';

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
      const raw =
          'https://github.com/Corpse-zhao/DataVision/releases/download/v1.0.5/DataVision-v1.0.5.apk';
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

  group('发布列表解析（踩过的坑：预发布版本被漏掉）', () {
    Map<String, dynamic> release(
      String tag, {
      bool draft = false,
      bool pre = false,
    }) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'body': '$tag 的说明',
      'html_url': 'https://github.com/Corpse-zhao/DataVision/releases/tag/$tag',
      'assets': [
        {
          'name': 'DataVision-$tag.apk',
          'browser_download_url':
              'https://github.com/Corpse-zhao/DataVision/releases/download/$tag/DataVision-$tag.apk',
          'size': 51235328,
        },
        {
          'name': 'DataVision-$tag.ipa',
          'browser_download_url':
              'https://github.com/Corpse-zhao/DataVision/releases/download/$tag/DataVision-$tag.ipa',
          'size': 6942996,
        },
      ],
    };

    test('标了 prerelease 的版本也必须算（就是这次 404 的根因）', () {
      final info = Updater.pickNewestRelease([
        release('v1.0.5', pre: true),
        release('v1.0.4'),
      ]);
      expect(info, isNotNull);
      expect(info!.version, '1.0.5');
      expect(info.apkSize, 51235328);
      expect(info.ipaSize, 6942996);
    });

    test('draft 不算', () {
      final info = Updater.pickNewestRelease([
        release('v1.0.7', draft: true),
        release('v1.0.6'),
      ]);
      expect(info!.version, '1.0.6');
    });

    test('按数字段挑最大，不按字符串顺序', () {
      final info = Updater.pickNewestRelease([
        release('v1.0.9'),
        release('v1.0.10'),
        release('v1.0.2'),
      ]);
      expect(info!.version, '1.0.10');
    });

    test('资产缺失时按命名规则拼地址', () {
      final info = Updater.pickNewestRelease([
        {'tag_name': 'v2.0.0', 'draft': false, 'assets': <dynamic>[]},
      ]);
      expect(
        info!.apkUrl,
        'https://github.com/Corpse-zhao/DataVision/releases/download/v2.0.0/DataVision-v2.0.0.apk',
      );
    });
  });

  group('version.json（API 不通时的备用线路）', () {
    test('能读出官方版本和下载地址', () {
      final info = Updater.infoFromStatic({
        'version': '1.3.2',
        'tag': 'v1.3.2',
        'notes': '修了什么',
      });
      expect(info!.version, '1.3.2');
      expect(info.tag, 'v1.3.2');
      expect(info.notes, '修了什么');
      expect(info.apkUrl, contains('/v1.3.2/DataVision-v1.3.2.apk'));
      expect(info.ipaUrl, contains('/v1.3.2/DataVision-v1.3.2.ipa'));
    });

    test('没有 tag 就用 v+版本号补', () {
      final info = Updater.infoFromStatic({'version': '2.0.0'});
      expect(info!.tag, 'v2.0.0');
    });
  });

  group('仓库里的 version.json', () {
    test('版本号必须和 pubspec 一致，否则更新通道会指向不存在的包', () {
      // 不用正则，省得转义出岔子
      final line = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
      final ver = line.split(':').last.split('+').first.trim();
      expect(ver, isNotEmpty, reason: 'pubspec 里读不到 version');

      final json = jsonDecode(
        File('version.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['version'], ver);
      expect(json['tag'], 'v$ver');
    });
  });
}
