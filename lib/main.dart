import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'ble/link.dart';
import 'ble/scanner.dart';
import 'core/prefs.dart';
import 'core/updater.dart';
import 'drivers/registry.dart';
import 'ui/bms_page.dart';
import 'ui/console_page.dart';
import 'ui/controller_page.dart';
import 'ui/settings_page.dart';
import 'ui/update_dialog.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final prefs = Prefs();
  await prefs.load();
  await Updater.instance.init();
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
  final _navKey = GlobalKey<NavigatorState>();
  final _msgKey = GlobalKey<ScaffoldMessengerState>();
  int _index = 0;
  bool _checkingUpdate = false;

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
    // 首帧之后再查，别和蓝牙初始化抢启动时间
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate(auto: true));
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
      // 后台待久了系统早把扫描停了，回来立刻补一次，不用等下一个窗口
      ScanBus.instance.restart();
      // 更新检查跟着前台节奏走，内部有 6 小时节流，不会每次都打接口
      _checkUpdate(auto: true);
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
      SettingsPage(
        prefs: widget.prefs,
        ctrl: ctrl,
        bms: bms,
        version: Updater.instance.displayVersion,
        onCheckUpdate: () => _checkUpdate(auto: false),
      ),
    ];

    return MaterialApp(
      title: '数据视界',
      navigatorKey: _navKey,
      scaffoldMessengerKey: _msgKey,
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

  /// 查更新。auto=true 时受 6 小时节流，静默失败；手动点就一定要给个回音。
  Future<void> _checkUpdate({bool auto = false}) async {
    if (_checkingUpdate) return;
    if (auto && !widget.prefs.shouldCheckUpdate()) return;
    _checkingUpdate = true;
    try {
      if (!auto) _toast('正在检查更新…');
      final info = await Updater.instance.check();
      await widget.prefs.markUpdateChecked();
      if (!mounted) return;
      if (info == null) {
        if (!auto) _toast('已经是最新版本 ${Updater.instance.displayVersion}');
        return;
      }
      final ctx = _navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final result = await showUpdateDialog(ctx, info);
      if (!mounted) return;
      if (result == 'installing') {
        _toast('安装包已交给系统，按提示完成覆盖安装');
      } else if (result == 'opened') {
        _toast('已在浏览器打开，下载后用全能签重新签名安装');
      }
    } on DownloadFailed catch (e) {
      if (!auto && mounted) _toast(e.message);
    } catch (_) {
      if (!auto && mounted) _toast('检查更新失败');
    } finally {
      _checkingUpdate = false;
    }
  }

  void _toast(String text) {
    _msgKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
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
