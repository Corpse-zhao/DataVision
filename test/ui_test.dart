import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datavision/ble/link.dart';
import 'package:datavision/core/prefs.dart';
import 'package:datavision/core/updater.dart';
import 'package:datavision/drivers/jk_bms.dart';
import 'package:datavision/drivers/lingbo.dart';
import 'package:datavision/drivers/registry.dart';
import 'package:datavision/ui/console_page.dart';
import 'package:datavision/ui/data_page.dart';
import 'package:datavision/ui/settings_page.dart';
import 'package:datavision/ui/update_dialog.dart';
import 'package:datavision/ui/theme.dart';

import 'protocol_test.dart' as frames;

/// 界面冒烟测试：用真实解析出来的数据把三个页面渲染一遍。
/// 目的不是"好看不好看"，是抓 RenderFlex overflow 和空值崩溃——
/// 手机上这些会变成黄色斑马纹或者白屏，肉眼很难在代码里发现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Prefs prefs;
  late BleLink ctrl;
  late BleLink bms;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = Prefs();
    await prefs.load();
    ctrl = BleLink(role: 'controller', pool: controllerDrivers(), prefs: prefs);
    bms = BleLink(role: 'bms', pool: bmsDrivers(), prefs: prefs);
  });

  void feedController() {
    final d = LingboDriver();
    d.feed(frames.lingboCalibration());
    d.feed(frames.lingboRealtime());
    ctrl.driver = d;
  }

  void feedBms() {
    final d = JkBmsDriver();
    d.feed(frames.jkCellFrame(cells: 16));
    bms.driver = d;
  }

  Future<void> pumpAt(WidgetTester tester, Widget page, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPalettes.classic),
        home: Scaffold(body: page),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('数据页竖屏：控制器在上、保护板在下，都不溢出（390x844）', (tester) async {
    feedController();
    feedBms();
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(390, 844));
    expect(tester.takeException(), isNull);
    // 控制器主指标
    expect(find.text('母线电压'), findsOneWidget);
    // 数值和单位在同一个 Text.rich 里（"60.3V"），所以按包含匹配
    expect(find.textContaining('60.3'), findsOneWidget);
    // 保护板主指标 + 单体条形带的两端标注
    expect(find.text('电量'), findsOneWidget);
    expect(find.textContaining('最高'), findsOneWidget);
    expect(find.textContaining('最低'), findsOneWidget);
    // 两张卡都在同一页（标题带里类名和品牌是分开的两段，不再是「凌博 · 控制器」）
    expect(find.text('控制器'), findsOneWidget);
    expect(find.text('保护板'), findsOneWidget);
  });

  testWidgets('数据页横屏：左右分栏也不溢出（844x390）', (tester) async {
    feedController();
    feedBms();
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.text('母线电压'), findsOneWidget);
    expect(find.text('电量'), findsOneWidget);
  });

  testWidgets('数据页小屏也不溢出（360x600）', (tester) async {
    feedController();
    feedBms();
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(360, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据页空态：两边各给一个搜索入口', (tester) async {
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('还没连控制器'), findsOneWidget);
    expect(find.text('还没连保护板'), findsOneWidget);
  });

  testWidgets('数据页空态横屏也不溢出（844x390）', (tester) async {
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.text('还没连控制器'), findsOneWidget);
    expect(find.text('还没连保护板'), findsOneWidget);
  });

  testWidgets('功率走势：两帧之后才画曲线，只有一帧不画', (tester) async {
    final d = LingboDriver();
    d.feed(frames.lingboCalibration());
    d.feed(frames.lingboRealtime());
    ctrl.driver = d;
    await pumpAt(tester, DataPage(ctrl: ctrl, bms: bms), const Size(390, 844));
    // 只有一帧（时间戳相同）→ 不算曲线，标题行不出现
    expect(find.text('功率 · 近 60 秒'), findsNothing);

    final trend = PowerTrend();
    final t0 = DateTime(2026, 1, 1, 12);
    trend.sample(t0, 300);
    expect(trend.hasCurve, isFalse);
    trend.sample(t0, 300); // 同一帧重复进，不该记两次
    expect(trend.values.length, 1);
    trend.sample(t0.add(const Duration(milliseconds: 40)), 500);
    trend.sample(t0.add(const Duration(milliseconds: 80)), 400);
    expect(trend.hasCurve, isTrue);
    expect(trend.peak, 500);
    expect(trend.average, closeTo(400, .01));
    // 超过窗口的老点要被丢掉
    trend.sample(t0.add(const Duration(seconds: 120)), 200);
    expect(trend.values.length, 1);
  });

  testWidgets('数据台与设置页能渲染', (tester) async {
    feedController();
    await pumpAt(
      tester,
      ConsolePage(ctrl: ctrl, bms: bms),
      const Size(390, 844),
    );
    expect(tester.takeException(), isNull);

    await pumpAt(
      tester,
      SettingsPage(
        prefs: prefs,
        ctrl: ctrl,
        bms: bms,
        version: 'v1.0.7',
        onCheckUpdate: () {},
        onOpenDownloadPage: () {},
        onOpenUpdate: () {},
      ),
      const Size(390, 844),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('自动连接'), findsOneWidget);
    // 没查到新版本时不该出现这个提示
    expect(find.text('检测到新版本'), findsNothing);
  });

  testWidgets('设置页有不息屏开关，打开后记进本地', (tester) async {
    await pumpAt(
      tester,
      SettingsPage(
        prefs: prefs,
        ctrl: ctrl,
        bms: bms,
        version: 'v1.0.8',
        onCheckUpdate: () {},
        onOpenDownloadPage: () {},
        onOpenUpdate: () {},
      ),
      // 画布拉高：「显示」这一节在列表中部，默认 640 高会构建不到
      const Size(390, 1400),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('不息屏'), findsOneWidget);
    // 默认关
    expect(prefs.keepAwake, isFalse);

    // 第 2 个 Switch 才是「不息屏」（第 1 个是自动连接）
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(prefs.keepAwake, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查到新版本时版本号旁边出现提示', (tester) async {
    feedController();
    await pumpAt(
      tester,
      SettingsPage(
        prefs: prefs,
        ctrl: ctrl,
        bms: bms,
        version: 'v1.0.6',
        onCheckUpdate: () {},
        onOpenDownloadPage: () {},
        update: const UpdateInfo(
          tag: 'v1.0.7',
          version: '1.0.7',
          notes: '修了点什么',
          apkUrl: 'https://example.com/a.apk',
          ipaUrl: 'https://example.com/a.ipa',
          apkSize: 51235328,
          ipaSize: 6942996,
          pageUrl: 'https://example.com/releases',
        ),
        onOpenUpdate: () {},
      ),
      // 画布给高一点：设置页是长列表，「关于」在最后，默认 640 高度不会构建到那里
      const Size(390, 1800),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('检测到新版本'), findsOneWidget);
    // 版本号只显示 v1.0.6，不带括号里的构建号
    expect(find.text('v1.0.6'), findsOneWidget);
  });

  testWidgets('更新弹窗在小屏上不溢出', (tester) async {
    // 把窗口压到 360x640，模拟还没适配大屏的老机型
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPalettes.classic),
        home: Scaffold(
          body: UpdateDialog(
            info: const UpdateInfo(
              tag: 'v1.0.5',
              version: '1.0.5',
              notes:
                  '1. 安卓端支持 App 内直接下载更新，覆盖安装不用卸载\n'
                  '2. 修了回到前台后扫描不恢复的问题\n'
                  '3. 极空保护板温度偏移取错一位',
              apkUrl: 'https://example.com/a.apk',
              ipaUrl: 'https://example.com/a.ipa',
              apkSize: 51235328,
              ipaSize: 6942996,
              pageUrl: 'https://example.com/releases',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('发现新版本 v1.0.5'), findsOneWidget);
    // 测试跑在桌面端，Platform.isAndroid 为 false，走的是 iOS 文案分支
    expect(find.textContaining('下载 IPA'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
  });

  group('连上了但没数据的诊断文案', () {
    test('0 字节：说清是链路层问题，并带上通知口', () {
      final l = BleLink(
        role: 'controller',
        pool: controllerDrivers(),
        prefs: prefs,
      );
      l.rxBytes = 0;
      l.notifyInfo = '2 个（FFE1、FFE2）';
      final t = diagnose(l, '控制器');
      expect(t, contains('0 字节'));
      expect(t, contains('FFE1'));
    });

    test('通知口一个都没订上时不能显示空白', () {
      final l = BleLink(
        role: 'controller',
        pool: controllerDrivers(),
        prefs: prefs,
      );
      l.rxBytes = 0;
      final t = diagnose(l, '控制器');
      expect(t, contains('没订上'));
    });

    test('有字节但没帧：指向协议问题，要原始字节', () {
      final l = BleLink(
        role: 'controller',
        pool: controllerDrivers(),
        prefs: prefs,
      );
      l.rxCount = 3;
      l.rxBytes = 48;
      final t = diagnose(l, '控制器');
      expect(t, contains('48 字节'));
      expect(t, contains('最近帧'));
    });
  });

  group('主题', () {
    test('内置五套，id 唯一，深浅各半', () {
      final all = AppPalettes.all;
      expect(all.length, 5);
      expect(all.map((p) => p.id).toSet().length, 5);
      expect(all.map((p) => p.name).toSet().length, 5);
      expect(all.where((p) => p.brightness == Brightness.dark).length, 3);
    });

    test('未知 id 回落到浅色，不会崩', () {
      expect(AppPalettes.byId('不存在').id, 'classic');
      expect(AppPalettes.byId(null).id, 'classic');
      AppThemeManager.instance.restore('不存在');
      expect(AppThemeManager.instance.id, 'classic');
    });

    test('换主题后 AppColors 跟着变', () {
      AppThemeManager.instance.restore('classic');
      expect(AppColors.bg, AppPalettes.classic.bg);
      expect(AppColors.isDark, isFalse);
      expect(AppColors.numberGlow, isNull);

      AppThemeManager.instance.select('hud');
      expect(AppColors.bg, AppPalettes.hud.bg);
      expect(AppColors.accent, AppPalettes.hud.accent);
      expect(AppColors.isDark, isTrue);
      // 车载主题的数字要发光
      expect(AppColors.numberGlow, isNotNull);
      expect(AppColors.numberScale, greaterThan(1));

      AppThemeManager.instance.restore('classic');
    });

    testWidgets('设置页点缩略图就能换主题，并记进本地', (tester) async {
      AppThemeManager.instance.restore('classic');
      expect(prefs.themeId, 'classic');

      await pumpAt(
        tester,
        SettingsPage(
          prefs: prefs,
          ctrl: ctrl,
          bms: bms,
          version: 'v1.0.11',
          onCheckUpdate: () {},
          onOpenDownloadPage: () {},
          onOpenUpdate: () {},
        ),
        const Size(390, 1400),
      );

      // 缩略图是横向滚动的：先看得到的前四套，最后一套拖出来
      for (final p in AppPalettes.all.take(4)) {
        expect(find.text(p.name), findsOneWidget);
      }
      expect(find.text(AppPalettes.daylight.name), findsNothing);
      // 外层是竖向列表，主题条是里面的横向 ListView
      await tester.drag(find.byType(ListView).at(1), const Offset(-200, 0));
      await tester.pump();
      expect(find.text(AppPalettes.daylight.name), findsOneWidget);
      // 拖回去，保证「夜色」在可点范围内
      await tester.drag(find.byType(ListView).at(1), const Offset(200, 0));
      await tester.pump();

      await tester.tap(find.text('夜色'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(AppThemeManager.instance.id, 'midnight');
      expect(prefs.themeId, 'midnight');
      expect(AppColors.bg, AppPalettes.midnight.bg);

      AppThemeManager.instance.restore('classic');
    });

    testWidgets('深色主题下数据页也不溢出（390x844）', (tester) async {
      feedController();
      feedBms();
      AppThemeManager.instance.restore('amber');
      await pumpAt(
        tester,
        DataPage(ctrl: ctrl, bms: bms),
        const Size(390, 844),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('母线电压'), findsOneWidget);
      AppThemeManager.instance.restore('classic');
    });
  });
}
