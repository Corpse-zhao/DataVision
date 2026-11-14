// 临时：把五套主题各渲染一张图，出 PNG 给用户看效果（不参与提交）
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datavision/ble/link.dart';
import 'package:datavision/core/prefs.dart';
import 'package:datavision/drivers/jk_bms.dart';
import 'package:datavision/drivers/lingbo.dart';
import 'package:datavision/drivers/registry.dart';
import 'package:datavision/ui/data_page.dart';
import 'package:datavision/ui/settings_page.dart';
import 'package:datavision/ui/theme.dart';

import '../protocol_test.dart' as frames;

Future<void> loadFont(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadFont('Microsoft YaHei', r'C:\Windows\Fonts\simhei.ttf');
    await loadFont('Consolas', r'C:\Windows\Fonts\consola.ttf');
  });

  late Prefs prefs;
  late BleLink ctrl;
  late BleLink bms;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = Prefs();
    await prefs.load();
    ctrl = BleLink(role: 'controller', pool: controllerDrivers(), prefs: prefs);
    bms = BleLink(role: 'bms', pool: bmsDrivers(), prefs: prefs);
    final d = LingboDriver()..feed(frames.lingboCalibration());
    ctrl.driver = d;
    final b = JkBmsDriver()..feed(frames.jkCellFrame(cells: 16));
    bms.driver = b;
  });

  Widget app(AppPalette pal, Size size) => MaterialApp(
        theme: AppTheme.of(pal),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ThemeBackdrop(
            child: Column(
              children: [
                Container(
                  height: 40,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('数据视界 · ${pal.name}',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                Expanded(child: DataPage(ctrl: ctrl, bms: bms)),
              ],
            ),
          ),
        ),
      );

  Future<void> shot(WidgetTester tester, String name, AppPalette pal, Size size) async {
    AppThemeManager.instance.restore(pal.id);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(pal, size));
    // 喂一串递增的电流，让功率走势攒出一条真曲线（每喂一次时间戳就变，页面会重新采样）
    final amps = [300, 620, 980, 1500, 2050, 1780, 1240, 860, 1180, 1620, 2100, 1900];
    for (var i = 0; i < amps.length; i++) {
      ctrl.driver!.feed(frames.lingboRealtime(rawAmps: amps[i], rpm: 900 + i * 120));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
      await tester.pumpWidget(app(pal, size));
    }
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
  }

  for (final p in AppPalettes.all) {
    testWidgets('shot ${p.id}', (tester) async {
      await shot(tester, p.id, p, const Size(390, 844));
    });
  }

  testWidgets('shot hud landscape', (tester) async {
    await shot(tester, 'hud_land', AppPalettes.hud, const Size(844, 390));
  });

  Future<void> shotSettings(WidgetTester tester, AppPalette pal) async {
    AppThemeManager.instance.restore(pal.id);
    tester.view.physicalSize = const Size(390, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(pal),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: ThemeBackdrop(
          child: SettingsPage(
            prefs: prefs,
            ctrl: ctrl,
            bms: bms,
            version: 'v1.0.11',
            onCheckUpdate: () {},
            onOpenDownloadPage: () {},
            onOpenUpdate: () {},
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/settings_${pal.id}.png'));
  }

  testWidgets('shot settings classic', (tester) async => shotSettings(tester, AppPalettes.classic));
  testWidgets('shot settings hud', (tester) async => shotSettings(tester, AppPalettes.hud));
}
