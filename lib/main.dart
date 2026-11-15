import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'ble/link.dart';
import 'ble/scanner.dart';
import 'core/native.dart';
import 'core/prefs.dart';
import 'core/updater.dart';
import 'drivers/registry.dart';
import 'ui/console_page.dart';
import 'ui/data_page.dart';
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
  // 主题要在第一帧之前定下来，免得开机闪一下浅色再变深色
  AppThemeManager.instance.restore(prefs.themeId);
  await Updater.instance.init();
  runApp(DataVisionApp(prefs: prefs));
}

class DataVisionApp extends StatefulWidget {
  final Prefs prefs;
  const DataVisionApp({super.key, required this.prefs});

  @override
  State<DataVisionApp> createState() => _DataVisionAppState();
}

class _DataVisionAppState extends State<DataVisionApp>
    with WidgetsBindingObserver {
  late final BleLink ctrl;
  late final BleLink bms;
  final _navKey = GlobalKey<NavigatorState>();
  final _msgKey = GlobalKey<ScaffoldMessengerState>();
  int _index = 0;
  bool _checkingUpdate = false;

  /// 查到的新版本；null 表示没有（或还没查过）。设置页靠它显示「检测到新版本」
  UpdateInfo? _available;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = BleLink(
      role: 'controller',
      pool: controllerDrivers(),
      prefs: widget.prefs,
    );
    bms = BleLink(role: 'bms', pool: bmsDrivers(), prefs: widget.prefs);
    ctrl.addListener(_refresh);
    bms.addListener(_refresh);
    // 连上任意一条后，全局扫描降频：边连边全速扫会抢射频，已连的设备开始丢包
    ScanBus.instance.busyProbe = () => ctrl.connected || bms.connected;
    ctrl.init();
    bms.init();
    // 上次开的常亮，这次启动接着生效（默认关，不会平白多耗电）
    Native.setKeepAwake(widget.prefs.keepAwake);
    // 首帧之后再查，别和蓝牙初始化抢启动时间
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkUpdate(auto: true),
    );
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
      // 回前台重新挂一次常亮标记：切后台期间系统会把窗口标志清掉
      Native.setKeepAwake(widget.prefs.keepAwake);
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
      DataPage(ctrl: ctrl, bms: bms),
      ConsolePage(ctrl: ctrl, bms: bms),
      SettingsPage(
        prefs: widget.prefs,
        ctrl: ctrl,
        bms: bms,
        version: Updater.instance.displayVersion,
        onCheckUpdate: () => _checkUpdate(auto: false),
        onOpenDownloadPage: () => Updater.instance.openDownloadPage(),
        update: _available,
        onOpenUpdate: _openUpdateDialog,
      ),
    ];

    final size = MediaQuery.sizeOf(context);
    final wide = size.width > size.height;

    return AnimatedBuilder(
      animation: AppThemeManager.instance,
      builder: (context, _) {
        final pal = AppThemeManager.instance.palette;
        return MaterialApp(
          title: '数据视界',
          navigatorKey: _navKey,
          scaffoldMessengerKey: _msgKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.of(pal),
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            // 深色主题下状态栏图标要转成白字，否则在纯黑底上看不见
            value: pal.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: Scaffold(
              appBar: AppBar(
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                titleSpacing: 16,
                title: Row(
                  children: [
                    Text(
                      '数据视界',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _dot(ctrl.phase == LinkPhase.online, '控'),
                    const SizedBox(width: 5),
                    _dot(bms.phase == LinkPhase.online, '板'),
                  ],
                ),
                // 横屏时底部导航条太占地方，标签收进顶栏右上角
                actions: wide
                    ? [
                        _PlateTabs(
                          index: _index,
                          onTap: (i) => setState(() => _index = i),
                        ),
                        const SizedBox(width: 12),
                      ]
                    : null,
              ),
              body: ThemeBackdrop(
                child: IndexedStack(index: _index, children: pages),
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      height: 58,
                      backgroundColor: AppColors.card,
                      indicatorColor: AppColors.accent.withValues(alpha: .10),
                      selectedIndex: _index,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.speed_outlined),
                          selectedIcon: Icon(Icons.speed),
                          label: '数据',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.terminal_outlined),
                          selectedIcon: Icon(Icons.terminal),
                          label: '数据台',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: '设置',
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
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
      if (_available?.version != info?.version) {
        setState(() => _available = info);
      }
      if (info == null) {
        if (!auto) _toast('已经是最新版本 ${Updater.instance.displayVersion}');
        return;
      }
      await _openUpdateDialog();
      return;
    } on DownloadFailed catch (e) {
      // 查不到版本时不要只留一句"失败"，直接给个能点的手动出口
      if (!auto && mounted) {
        _toast(e.message, action: '打开下载页');
      }
    } catch (_) {
      if (!auto && mounted) _toast('检查更新失败');
    } finally {
      _checkingUpdate = false;
    }
  }

  /// 弹更新面板（自动查到、或设置页点「检测到新版本」都走这里）
  Future<void> _openUpdateDialog() async {
    final info = _available;
    if (info == null) return;
    final ctx = _navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final result = await showUpdateDialog(ctx, info);
    if (!mounted) return;
    if (result == 'installing') {
      _toast('安装包已交给系统，按提示完成覆盖安装');
    } else if (result == 'opened') {
      _toast('已在浏览器打开，下载后用全能签重新签名安装');
    }
  }

  void _toast(String text, {String? action}) {
    _msgKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: action == null ? 3 : 6),
        action: action == null
            ? null
            : SnackBarAction(
                label: action,
                onPressed: () => Updater.instance.openDownloadPage(),
              ),
      ),
    );
  }

  Widget _dot(bool on, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: on
            ? AppColors.good.withValues(alpha: .12)
            : AppColors.line.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.good
                  : AppColors.inkSoft.withValues(alpha: .4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: on ? AppColors.good : AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 横屏顶栏上的三个标签（代替底部导航条）
class _PlateTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _PlateTabs({required this.index, required this.onTap});

  static const _labels = ['数据', '数据台', '设置'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: i == index
                      ? AppColors.accent.withValues(alpha: .10)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                    color: i == index ? AppColors.accent : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
