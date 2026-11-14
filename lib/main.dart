import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'ble/link.dart';
import 'core/prefs.dart';
import 'drivers/registry.dart';
import 'ui/bms_page.dart';
import 'ui/console_page.dart';
import 'ui/controller_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

const appVersion = '1.0.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final prefs = Prefs();
  await prefs.load();
  runApp(DataVisionApp(prefs: prefs));
}

class DataVisionApp extends StatefulWidget {
  final Prefs prefs;
  const DataVisionApp({super.key, required this.prefs});

  @override
  State<DataVisionApp> createState() => _DataVisionAppState();
}

class _DataVisionAppState extends State<DataVisionApp> with WidgetsBindingObserver {
  late final BleLink ctrl;
  late final BleLink bms;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = BleLink(role: 'controller', pool: controllerDrivers(), prefs: widget.prefs);
    bms = BleLink(role: 'bms', pool: bmsDrivers(), prefs: widget.prefs);
    ctrl.addListener(_refresh);
    bms.addListener(_refresh);
    ctrl.init();
    bms.init();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回来：扫描早被系统停了，直接把两条链路都叫起来
      if (!ctrl.connected) ctrl.startScan(auto: true);
      if (!bms.connected) bms.startScan(auto: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ctrl.dispose();
    bms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ControllerPage(link: ctrl),
      BmsPage(link: bms),
      ConsolePage(ctrl: ctrl, bms: bms),
      SettingsPage(prefs: widget.prefs, ctrl: ctrl, bms: bms, version: appVersion),
    ];

    return MaterialApp(
      title: '数据视界',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: Row(
            children: [
              const Text('数据视界',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: .5)),
              const SizedBox(width: 10),
              _dot(ctrl.phase == LinkPhase.online, '控'),
              const SizedBox(width: 6),
              _dot(bms.phase == LinkPhase.online, '板'),
            ],
          ),
        ),
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          height: 62,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.accent.withValues(alpha: .10),
          selectedIndex: _index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.memory_outlined), selectedIcon: Icon(Icons.memory), label: '控制器'),
            NavigationDestination(
                icon: Icon(Icons.battery_std_outlined),
                selectedIcon: Icon(Icons.battery_std),
                label: '保护板'),
            NavigationDestination(
                icon: Icon(Icons.terminal_outlined),
                selectedIcon: Icon(Icons.terminal),
                label: '数据台'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置'),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool on, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: on ? AppColors.good.withValues(alpha: .12) : AppColors.line.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: on ? AppColors.good : AppColors.inkSoft.withValues(alpha: .4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 10,
                color: on ? AppColors.good : AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
