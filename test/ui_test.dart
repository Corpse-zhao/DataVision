import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datavision/ble/link.dart';
import 'package:datavision/core/prefs.dart';
import 'package:datavision/core/updater.dart';
import 'package:datavision/drivers/jk_bms.dart';
import 'package:datavision/drivers/lingbo.dart';
import 'package:datavision/drivers/registry.dart';
import 'package:datavision/ui/bms_page.dart';
import 'package:datavision/ui/console_page.dart';
import 'package:datavision/ui/controller_page.dart';
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
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: page),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('控制器页有数据时布局不溢出（竖屏 390）', (tester) async {
    feedController();
    await pumpAt(tester, ControllerPage(link: ctrl), const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('母线电压'), findsOneWidget);
    expect(find.text('60.3'), findsOneWidget);
  });

  testWidgets('控制器页横屏也正常（844x390）', (tester) async {
    feedController();
    await pumpAt(tester, ControllerPage(link: ctrl), const Size(844, 390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制器页空态', (tester) async {
    await pumpAt(tester, ControllerPage(link: ctrl), const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('还没连控制器'), findsOneWidget);
  });

  testWidgets('保护板页渲染 16 串单体网格', (tester) async {
    feedBms();
    await pumpAt(tester, BmsPage(link: bms), const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('单体电压（16S）'), findsOneWidget);
  });

  testWidgets('保护板页小屏也不溢出（360x640）', (tester) async {
    feedBms();
    await pumpAt(tester, BmsPage(link: bms), const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据台与设置页能渲染', (tester) async {
    feedController();
    await pumpAt(tester, ConsolePage(ctrl: ctrl, bms: bms), const Size(390, 844));
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
          onOpenUpdate: () {}),
      const Size(390, 844),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('自动连接'), findsOneWidget);
    // 没查到新版本时不该出现这个提示
    expect(find.text('检测到新版本'), findsNothing);
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

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: UpdateDialog(
          info: const UpdateInfo(
            tag: 'v1.0.5',
            version: '1.0.5',
            notes: '1. 安卓端支持 App 内直接下载更新，覆盖安装不用卸载\n'
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
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('发现新版本 v1.0.5'), findsOneWidget);
    // 测试跑在桌面端，Platform.isAndroid 为 false，走的是 iOS 文案分支
    expect(find.textContaining('下载 IPA'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
  });
}
