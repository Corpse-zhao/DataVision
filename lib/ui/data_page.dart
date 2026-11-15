import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/models.dart';
import 'link_header.dart';
import 'theme.dart';

/// 一屏数据页：
///   竖屏 —— 上面控制器、下面保护板
///   横屏 —— 左控制器、右保护板（横屏时底部导航由 main 收进顶栏）
///
/// 版面原则：格子小、信息密。格子不放大，靠「两行指标 + 功率走势 + 单体条形带
/// + 电量条」把整屏填满 —— 富余高度交给图和柱，而不是平均摊成留白。
class DataPage extends StatefulWidget {
  final BleLink ctrl;
  final BleLink bms;
  const DataPage({super.key, required this.ctrl, required this.bms});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  late final Listenable _both = Listenable.merge([widget.ctrl, widget.bms]);
  final PowerTrend _trend = PowerTrend(window: const Duration(seconds: 60));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _both,
      builder: (context, _) {
        final cd = widget.ctrl.controller;
        // 每来一帧就把功率记一笔（同一帧重复 build 不会重复记）
        if (cd != null) _trend.sample(cd.at, powerOf(cd.primary));

        final ctrlCard = _ControllerCard(link: widget.ctrl, trend: _trend);
        final bmsCard = _BmsCard(link: widget.bms);

        return LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            return Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, wide ? 10 : 6),
              child: wide
                  ? Row(
                      children: [
                        Expanded(flex: 10, child: ctrlCard),
                        const SizedBox(width: 9),
                        Expanded(flex: 11, child: bmsCard),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(flex: 5, child: ctrlCard),
                        const SizedBox(height: 9),
                        Expanded(flex: 6, child: bmsCard),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

// MARK: - 功率走势缓冲

/// 60 秒功率环形缓冲。只做两件事：记数、算峰/均。
/// 不落盘；25Hz 跑满 60 秒约 1500 点，按 600 点截断够画了。
class PowerTrend {
  final Duration window;
  final List<_TrendPoint> _pts = [];
  PowerTrend({this.window = const Duration(seconds: 60)});

  void sample(DateTime at, double? watts) {
    if (watts == null) return;
    if (_pts.isNotEmpty && _pts.last.at == at) return; // 同一帧
    _pts.add(_TrendPoint(at, watts));
    final cut = at.subtract(window);
    while (_pts.isNotEmpty && _pts.first.at.isBefore(cut)) {
      _pts.removeAt(0);
    }
    if (_pts.length > 600) _pts.removeRange(0, _pts.length - 600);
  }

  List<double> get values => [for (final p in _pts) p.watts];
  bool get hasCurve => _pts.length >= 2;

  double? get peak =>
      _pts.isEmpty ? null : _pts.map((p) => p.watts).reduce(math.max);
  double? get average => _pts.isEmpty
      ? null
      : _pts.map((p) => p.watts).reduce((a, b) => a + b) / _pts.length;
}

class _TrendPoint {
  final DateTime at;
  final double watts;
  _TrendPoint(this.at, this.watts);
}

// MARK: - 取值小工具

/// 从一组指标里按关键字找（协议不同，标签写法会有出入）
Metric? findMetric(List<Metric> list, List<String> keys) {
  for (final m in list) {
    for (final k in keys) {
      if (m.label.contains(k)) return m;
    }
  }
  return null;
}

/// 功率统一换成 W 的数值，走势图要用
double? powerOf(List<Metric> list) {
  final m = findMetric(list, const ['功率']);
  if (m == null) return null;
  final v = double.tryParse(m.value.replaceAll(',', ''));
  if (v == null) return null;
  return m.unit == 'kW' ? v * 1000 : v;
}

String thousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 「连上了但没数据」时的诊断说明。
///
/// 这两种情况差得很远，必须分开说：
///   0 字节  → 订阅没订上 / 板子没在推，属于链路层问题
///   有字节  → 帧头或校验对不上，属于协议问题，要看原始字节
String diagnose(BleLink link, String what) {
  if (link.rxBytes == 0) {
    final notify = link.notifyInfo.isEmpty ? '没订上任何一个' : link.notifyInfo;
    return '现状：0 字节 · 通知口 $notify\n'
        '把这两行连同「数据台」里的信道一起发我，能判断是订阅问题还是$what不推数据。';
  }
  return '现状：收到 ${link.rxCount} 包 / ${link.rxBytes} 字节，但没解析出完整帧\n'
      '链路是通的，差的只是帧格式（多半换了新固件）。'
      '把「数据台 → 最近帧」那串十六进制发我，我按新固件加协议。';
}

/// 驱动名压成短品牌：「凌博 LBMC」→「凌博」，「蚂蚁保护板（ANT）」→「蚂蚁」
String brandOf(String? driverName, String fallback) {
  if (driverName == null || driverName.isEmpty) return fallback;
  var s = driverName.split('（').first.split('(').first.trim();
  s = s.replaceAll('保护板', '').replaceAll('控制器', '').trim();
  s = s.split(' ').first;
  return s.isEmpty ? fallback : s;
}

// MARK: - 卡片外框

/// 卡片：标题带 + 通栏指标条 + 正文 + 通栏页脚。
///
/// 标题带的信息按权重分三层：状态点（最响）→ 设备类名（中黑）→ 品牌（小灰）。
/// 之前三者挤在一行同字号里，扫一眼分不出「这是控制器」还是「这是凌博」。
///
/// 指标条做成**通栏**（出血到卡片左右边）而不是缩进的一块：
/// 缩进条里的字会比下面一行字多缩进 16px，两行左边缘对不上，整卡都在"歪"。
/// 出血之后条内文字正好落在 14px 版心线上，与正文严格对齐。
class _CardFrame extends StatelessWidget {
  final Color dot;
  final String title;
  final String? brand;
  final Widget? trailing;
  final Widget? band;
  final Widget Function(double bodyH) body;
  final Widget? footer;

  const _CardFrame({
    required this.dot,
    required this.title,
    this.brand,
    this.trailing,
    this.band,
    required this.body,
    this.footer,
  });

  static const _headH = 19.0;
  static const _bandH = 64.0;
  static const _footerH = 34.0;
  static const _padH = 14.0;

  @override
  Widget build(BuildContext context) {
    final bandH = band == null ? 0.0 : _bandH + 10;
    return Container(
      decoration: AppColors.cardBox(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final bodyH = math.max(
            0.0,
            box.maxHeight -
                _headH -
                11 -
                (footer == null ? 0 : _footerH + .5) -
                (band == null ? 9.5 : bandH) -
                20,
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_padH, 11, _padH - 4, 0),
                child: SizedBox(
                  height: _headH,
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: dot.withValues(alpha: .45),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2,
                          color: AppColors.ink,
                        ),
                      ),
                      if (brand != null && brand!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            brand!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
                ),
              ),
              if (band == null)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Container(height: .5, color: AppColors.line),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    height: _bandH,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      border: Border(
                        top: BorderSide(color: AppColors.hairline, width: .5),
                        bottom: BorderSide(
                          color: AppColors.hairline,
                          width: .5,
                        ),
                      ),
                    ),
                    child: band,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 10),
                  child: body(bodyH),
                ),
              ),
              if (footer != null)
                Container(
                  height: _footerH,
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    border: Border(
                      top: BorderSide(color: AppColors.hairline, width: .5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  alignment: Alignment.center,
                  child: footer,
                ),
            ],
          );
        },
      ),
    );
  }
}

// MARK: - 指标条

/// 一个指标：标签 + 数值 + 单位。
class _Tile {
  final String label;
  final String value;
  final String unit;

  /// null 表示跟随主题的字色（主题是运行时切的，不能写进 const 默认值）
  final Color? color;

  /// 主指标：整张卡只给一个。主指标用主题色 + 大一号 + 更强的光晕，
  /// 其余一律退回墨色 —— 八个数字全是重点等于没有重点。
  final bool primary;

  const _Tile({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
    this.primary = false,
  });

  factory _Tile.of(Metric m, {bool primary = false}) => _Tile(
    label: m.label,
    value: m.value,
    unit: m.unit,
    color: primary ? AppColors.accent : AppColors.tone(m.tone),
    primary: primary,
  );
}

/// 主指标条的内容：四格等分 + 三根竖细分隔。
///
/// 四个各自带底的方块会读成「四个按钮」，一整条铺底才读成「一块仪表」。
/// 底和上下细线由 [_CardFrame.band] 提供（要通栏），这里只管排布。
class _MetricBand extends StatelessWidget {
  final List<_Tile> tiles;
  const _MetricBand({required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0)
            Center(
              child: Container(width: .5, height: 30, color: AppColors.hairline),
            ),
          Expanded(child: _BandCell(tiles[i])),
        ],
      ],
    );
  }
}

class _BandCell extends StatelessWidget {
  final _Tile t;
  const _BandCell(this.t);

  @override
  Widget build(BuildContext context) {
    final scale = AppColors.numberScale;
    final main = t.primary ? 23.0 : 19.0;
    final tint = t.primary ? AppColors.accent : AppColors.inkSoft;
    final grad = t.primary ? AppColors.accentGrad : null;

    Widget number = Text.rich(
      TextSpan(
        text: t.value,
        children: [
          if (t.unit.isNotEmpty)
            TextSpan(
              text: ' ${t.unit}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: t.primary
                    ? AppColors.accent.withValues(alpha: .7)
                    : AppColors.inkSoft,
              ),
            ),
        ],
      ),
      maxLines: 1,
      style: AppTheme.mono.copyWith(
        fontSize: main * scale,
        height: 1,
        fontWeight: t.primary ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: -.4,
        color: t.color ?? AppColors.ink,
        // 渐变数字走 ShaderMask，阴影会被那层裁掉，所以光晕改用背后的径向底
        shadows: t.primary && grad == null
            ? AppColors.glowFor(strong: true)
            : null,
      ),
    );
    if (grad != null) {
      number = GradientText(colors: grad, child: number);
    }

    return Container(
      // 渐变主题里给主指标垫一层径向主色，代替被裁掉的文字光晕
      decoration: t.primary && grad != null
          ? BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-.35, .55),
                radius: 1.15,
                colors: [
                  AppColors.accent.withValues(alpha: AppColors.isDark ? .16 : .07),
                  AppColors.accent.withValues(alpha: 0),
                ],
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              letterSpacing: .3,
              fontWeight: t.primary ? FontWeight.w600 : FontWeight.w400,
              color: t.primary ? tint.withValues(alpha: .9) : tint,
            ),
          ),
          const SizedBox(height: 5),
          // 固定高度的底对齐槽：主次字号不同，只有按底对齐（数字无下伸部，
          // 视觉底边就是基线）四个数才会齐平，否则会像浪一样上下错
          SizedBox(
            height: 29,
            child: Align(
              alignment: Alignment.bottomLeft,
              // 窄屏（360）一行四格时 "3200rpm" 会顶出去，按比例缩而不是打省略号
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: number,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 次级指标行：标签在上、数值在下，没有底色，视觉上比主指标条轻一档。
class _FootRow extends StatelessWidget {
  final List<(String, String, String)> items; // (标签, 数值, 单位)
  final double valueSize;
  final double labelSize;
  const _FootRow(
    this.items, {
    this.valueSize = 12.5,
    this.labelSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelSize,
                    height: 1.1,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    text: it.$2,
                    children: [
                      if (it.$3.isNotEmpty)
                        TextSpan(
                          text: it.$3,
                          style: TextStyle(
                            fontSize: valueSize - 2.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono.copyWith(
                    fontSize: valueSize,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 小节标题：小字 + 一条通到右边的细线，用来把「图」和「数值」分开而不加框
class _SectionGap extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionGap(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.2,
            letterSpacing: .3,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: .5, color: AppColors.hairline),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// 标题带右侧的小状态标签。比 StatusPill 小一号，只用来放「运行正常 / 均衡待机」
class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniTag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isDark ? .16 : .10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// MARK: - 控制器卡

class _ControllerCard extends StatelessWidget {
  final BleLink link;
  final PowerTrend trend;
  const _ControllerCard({required this.link, required this.trend});

  @override
  Widget build(BuildContext context) {
    final data = link.controller;
    if (data == null) {
      final waiting = link.connected;
      return EmptyHint(
        link: link,
        icon: Icons.memory,
        connected: waiting,
        title: waiting ? '已连上，还没收到数据' : '还没连控制器',
        subtitle: waiting
            ? '远驱这类控制器是「连上就自己推」：先确认控制器已上电、点火开关打开。'
                  '\n还是空的话点下面重新连接，让它重新订阅一次。'
            : '支持凌博、远驱（Fardriver / VOTOL / YuanQu）、VESC 系'
                  '（Flipsky / MakerX / Trampa 等）。\n第一次手动选一下，以后自动连。',
        note: waiting ? diagnose(link, '控制器') : null,
      );
    }

    final fault = data.fault;
    final online = link.phase == LinkPhase.online;
    final primary = data.primary;
    final powerIdx = primary.indexWhere((m) => m.label.contains('功率'));
    final secondary = data.secondary.take(4).toList();

    final tiles = <_Tile>[
      for (var i = 0; i < primary.length && i < 4; i++)
        _Tile.of(primary[i], primary: i == powerIdx),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAllMetrics(context, link, '控制器全部数据'),
      child: _CardFrame(
        dot: AppColors.accent,
        title: '控制器',
        brand: brandOf(link.driver?.name, '未识别'),
        trailing: _MiniTag(
          fault != null ? '故障' : (online ? '运行正常' : '等数据'),
          fault != null
              ? AppColors.bad
              : (online ? AppColors.good : AppColors.inkSoft),
        ),
        band: _MetricBand(tiles: tiles),
        body: (h) {
          // 卡太扁（横屏或小屏）时，第二行指标让位给走势图
          final showSecondary = secondary.isNotEmpty && h > 140;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fault != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bad.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: AppColors.bad.withValues(alpha: .25),
                      width: .5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.bad,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fault,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.bad,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
              if (showSecondary) ...[
                const SizedBox(height: 11),
                _FootRow([
                  for (final m in secondary) (m.label, m.value, m.unit),
                ], valueSize: 14, labelSize: 10),
              ],
              const SizedBox(height: 12),
              // 图吃掉剩下的全部高度：图比格子高得越多越像仪表，不像表格
              Expanded(child: _SparkArea(trend: trend, frames: link.frameCount)),
            ],
          );
        },
        footer: _ProtocolFooter(
          name: link.driver?.name ?? '嗅探中',
          frames: link.frameCount,
        ),
      ),
    );
  }
}

/// 页脚：左边协议名、右边帧计数。两段都是"这条链路现在什么情况"的元信息，
/// 不需要图标 —— 12px 的小图标在这个尺寸只会糊成一团。
class _ProtocolFooter extends StatelessWidget {
  final String name;
  final int frames;
  const _ProtocolFooter({required this.name, required this.frames});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '协议',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.inkSoft.withValues(alpha: .7),
            letterSpacing: .3,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
          ),
        ),
        Text(
          '${thousands(frames)} 帧',
          style: AppTheme.mono.copyWith(fontSize: 10.5, color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

/// 功率走势区：吃掉控制器卡剩下的全部高度。
/// 还没攒够两帧就只画基线 + 一句提示，不留一块死白。
class _SparkArea extends StatelessWidget {
  final PowerTrend trend;
  final int frames;
  const _SparkArea({required this.trend, this.frames = 0});

  @override
  Widget build(BuildContext context) {
    String fmt(double? w) {
      if (w == null) return '--';
      final (v, u) = fmtPower(w);
      return '$v $u';
    }

    final curve = trend.hasCurve;
    // 收了 60 帧还没有功率，基本就是这套协议不含功率字段，别一直挂着「等曲线」
    final noPowerField = !curve && frames > 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionGap(
          '功率走势 · 60 秒',
          trailing: Text(
            curve
                ? '峰 ${fmt(trend.peak)} · 均 ${fmt(trend.average)}'
                : (noPowerField ? '该协议不上报功率' : '等曲线'),
            style: AppTheme.mono.copyWith(
              fontSize: 10,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: CustomPaint(
            painter: _SparkPainter(
              trend.values,
              AppColors.accent,
              grad: AppColors.accentGrad,
              grid: AppColors.gridLine,
              base: AppColors.hairline,
            ),
            child: curve
                ? null
                : Center(
                    child: Text(
                      noPowerField ? '这一路数据里没有功率，走势留空' : '跑起来几帧就出曲线',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkSoft.withValues(alpha: .8),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 虚线：图表里到处要用（网格、游标、均值参考线）
void _dash(Canvas canvas, Offset a, Offset b, Paint p, {double on = 3, double off = 4}) {
  final total = (b - a).distance;
  if (total <= 0) return;
  final dir = (b - a) / total;
  var d = 0.0;
  while (d < total) {
    final end = math.min(d + on, total);
    canvas.drawLine(a + dir * d, a + dir * end, p);
    d = end + off;
  }
}

/// 折线 + 面积渐变 + 竖向网格 + 末端游标。
///
/// 之前只有一条裸线和一根中线，读不出「现在在哪、涨到哪了」。现在补三样：
/// 竖向网格（时间刻度感）、线下渐变（有体量）、末端光点 + 竖虚线（定位当前值）。
class _SparkPainter extends CustomPainter {
  final List<double> pts;
  final Color color;
  final List<Color>? grad;
  final Color grid;
  final Color base;
  _SparkPainter(
    this.pts,
    this.color, {
    this.grad,
    required this.grid,
    required this.base,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;

    // 横网格：底部实线 + 上两层虚线，给折线一个「参考平面」
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = .8;
    for (final f in const [.34, .67]) {
      _dash(canvas, Offset(0, h * f), Offset(w, h * f), gridPaint);
    }
    canvas.drawLine(
      Offset(0, h - .5),
      Offset(w, h - .5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );

    if (pts.length < 2) return;

    var lo = pts.reduce(math.min);
    var hi = pts.reduce(math.max);
    // 一条直线（功率没变）时居中画，不要贴着底边
    final flat = hi - lo < 1;
    final pad = (hi - lo) * .12;
    lo -= pad;
    hi += pad;

    double top = 4;
    double bottom = h - 4;
    double yOf(double v) {
      if (flat) return (top + bottom) / 2;
      return bottom - (v - lo) / (hi - lo) * (bottom - top);
    }

    // 右边留 5px：末端光点半径 6，不留边会被画布裁掉一半
    final plotW = math.max(1.0, w - 5);
    final dx = plotW / (pts.length - 1);
    final line = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = dx * i;
      final y = yOf(pts[i]);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    // 线下渐变：同一条路径闭到底边，只填不描
    final area = Path.from(line)
      ..lineTo(plotW, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (grad?.first ?? color).withValues(alpha: .22),
            (grad?.first ?? color).withValues(alpha: .01),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (grad != null) {
      stroke.shader = LinearGradient(
        colors: grad!,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    } else {
      stroke.color = color;
    }
    canvas.drawPath(line, stroke);

    // 末端游标：竖虚线到基线 + 双层光点，一眼看出「现在就是这个值」
    final lastX = dx * (pts.length - 1);    final lastY = yOf(pts.last);
    _dash(
      canvas,
      Offset(lastX, lastY),
      Offset(lastX, h - .5),
      Paint()
        ..color = color.withValues(alpha: .30)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(lastX, lastY),
      6,
      Paint()..color = color.withValues(alpha: .18),
    );
    canvas.drawCircle(Offset(lastX, lastY), 2.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.pts.length != pts.length ||
      old.color != color ||
      old.grad != grad ||
      (pts.isNotEmpty && (old.pts.isEmpty || old.pts.last != pts.last));
}

// MARK: - 保护板卡

class _BmsCard extends StatelessWidget {
  final BleLink link;
  const _BmsCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final data = link.bms;
    if (data == null) {
      final waiting = link.connected;
      return EmptyHint(
        link: link,
        icon: Icons.battery_std,
        connected: waiting,
        title: waiting ? '已连上，还没收到数据' : '还没连保护板',
        subtitle: waiting
            ? '先确认保护板已上电、蓝牙没被官方 App 占着。'
                  '\n还是空的话点下面重新连接，让它重新订阅一次。'
            : '支持蚂蚁（ANT）和极空（JK）。\n蚂蚁板有三条信道，第一条不通会自动换第二条、第三条。',
        note: waiting ? diagnose(link, '保护板') : null,
      );
    }

    final primary = data.primary;
    // 保护板的主指标是电量，不是功率 —— 骑到哪都先看这个
    var headIdx = primary.indexWhere((m) => m.label.contains('电量'));
    if (headIdx < 0) headIdx = primary.indexWhere((m) => m.label.contains('功率'));
    final tiles = <_Tile>[
      for (var i = 0; i < primary.length && i < 4; i++)
        _Tile.of(primary[i], primary: i == headIdx),
    ];

    final remain = findMetric(data.secondary, const ['剩余容量']);
    final cycles = findMetric(data.secondary, const ['循环']);
    final mosT = data.temps.isEmpty ? null : data.temps.reduce(math.max);
    final tempSpread = data.temps.isEmpty
        ? null
        : data.temps.reduce(math.max) - data.temps.reduce(math.min);

    final flagText = data.protection.isNotEmpty
        ? data.protection.first
        : (data.warning.isNotEmpty ? data.warning.first : null);
    final balanceText = data.balancer ? '均衡中' : '均衡待机';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAllMetrics(context, link, '保护板全部数据'),
      child: _CardFrame(
        dot: AppColors.good,
        title: '保护板',
        brand: brandOf(link.driver?.name, '未识别'),
        trailing: _MiniTag(
          flagText ?? balanceText,
          flagText != null
              ? (data.protection.isNotEmpty ? AppColors.bad : AppColors.warn)
              : AppColors.inkSoft,
        ),
        band: _MetricBand(tiles: tiles),
        body: (h) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.cells.isNotEmpty) ...[
              _SectionGap(
                '单体电压 · ${data.cells.length} 串',
                trailing: Text(
                  '压差 ${(data.deltaV * 1000).toStringAsFixed(0)} mV',
                  style: AppTheme.mono.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: data.deltaV > 0.05 ? AppColors.warn : AppColors.good,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _CellBars(data: data)),
              const SizedBox(height: 7),
              _CellLegend(data: data),
            ],
            const SizedBox(height: 12),
            _SectionGap(
              '剩余容量',
              trailing: Text(
                remain == null
                    ? '${data.soc}%'
                    : '${remain.value} ${remain.unit} · ${data.soc}%',
                style: AppTheme.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 7),
            _SocBar(soc: data.soc),
          ],
        ),
        footer: _FootRow([
          ('MOS', mosT == null ? '--' : mosT.toStringAsFixed(0), '℃'),
          ('健康', data.soh == 0 ? '--' : '${data.soh}', '%'),
          ('循环', cycles?.value ?? '--', ''),
          (
            '温差',
            tempSpread == null ? '--' : tempSpread.toStringAsFixed(0),
            '℃',
          ),
        ], valueSize: 14, labelSize: 10),
      ),
    );
  }
}

/// 一节一根柱：最高标红、最低标蓝。
/// 纯数字看不出「压差是集中还是散」，换成柱形一眼就分得出来。
///
/// 柱高做了压平（30%~100%），否则十六节只差十几毫伏时全一样高、看不出差别；
/// 代价是柱高不再是绝对值，所以必须补一条「平均值参考线」把零点感找回来。
class _CellBars extends StatelessWidget {
  final BmsData data;
  const _CellBars({required this.data});

  @override
  Widget build(BuildContext context) {
    final cells = data.cells;
    final lo = cells.reduce(math.min);
    final hi = cells.reduce(math.max);
    final avg = cells.reduce((a, b) => a + b) / cells.length;

    double factorOf(double v) => hi - lo < 1e-9
        ? .55
        : .30 + .70 * ((v - lo) / (hi - lo));

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CellRefPainter(
                avg: factorOf(avg),
                base: AppColors.hairline,
                ref: AppColors.inkSoft.withValues(alpha: .5),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: cells.length > 24 ? .8 : 2,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: factorOf(cells[i]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: (i + 1) == data.maxIdx
                              ? AppColors.bad
                              : (i + 1) == data.minIdx
                              ? AppColors.cool
                              : AppColors.barIdle,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 柱状图的两条参考线：底部基线（零点）+ 平均值虚线（水平位置）
class _CellRefPainter extends CustomPainter {
  final double avg;
  final Color base;
  final Color ref;
  _CellRefPainter({required this.avg, required this.base, required this.ref});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (1 - avg);
    _dash(
      canvas,
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = ref
        ..strokeWidth = 1,
      on: 4,
      off: 5,
    );
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CellRefPainter old) =>
      old.avg != avg || old.base != base || old.ref != ref;
}

class _CellLegend extends StatelessWidget {
  final BmsData data;
  const _CellLegend({required this.data});

  @override
  Widget build(BuildContext context) {
    final cells = data.cells;
    final avg = cells.isEmpty
        ? 0.0
        : cells.reduce((a, b) => a + b) / cells.length;

    Widget dot(Color c) => Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

    // 三栏等比 + 各自 scaleDown：360 窄屏（或系统字体放大）时整栏等比缩小，
    // 而不是把 "3.300V" 变成省略号 —— 这三组数字是这张卡最该读清的东西。
    Widget cell(Widget child, Alignment align) => Expanded(
      child: Align(
        alignment: align,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align,
          child: child,
        ),
      ),
    );

    return Row(
      children: [
        cell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(AppColors.cool),
              Text.rich(
                TextSpan(
                  text: '#${data.minIdx} 最低 ',
                  children: [
                    TextSpan(
                      text: '${data.minV.toStringAsFixed(3)}V',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                style: AppTheme.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.cool,
                ),
              ),
            ],
          ),
          Alignment.centerLeft,
        ),
        cell(
          Text.rich(
            TextSpan(
              text: '平均 ',
              children: [
                TextSpan(
                  text: '${avg.toStringAsFixed(3)}V',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            style: AppTheme.mono.copyWith(
              fontSize: 10,
              color: AppColors.inkSoft,
            ),
          ),
          Alignment.center,
        ),
        cell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  text: '#${data.maxIdx} 最高 ',
                  children: [
                    TextSpan(
                      text: '${data.maxV.toStringAsFixed(3)}V',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                style: AppTheme.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.bad,
                ),
              ),
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: AppColors.bad,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          Alignment.centerRight,
        ),
      ],
    );
  }
}

/// 电量条：底槽 + 填充 + 四道刻度。
/// 刻度不是装饰 —— 20/40/60/80 这几个位置是判断「还能骑多远」的锚点。
class _SocBar extends StatelessWidget {
  final int soc;
  const _SocBar({required this.soc});

  static const _h = 8.0;

  @override
  Widget build(BuildContext context) {
    final value = (soc.clamp(0, 100)) / 100.0;
    final color = soc < 20
        ? AppColors.bad
        : (soc < 50 ? AppColors.warn : AppColors.good);
    return SizedBox(
      height: _h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_h / 2),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: AppColors.cardAlt)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: .78),
                        color,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 刻度：用卡片底色切出细缝，深浅主题下都看得见
            for (var i = 1; i < 5; i++)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: i / 5,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(width: 1.2, color: AppColors.card),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: - 全部数据（点卡片弹出）

void _showAllMetrics(BuildContext context, BleLink link, String title) {
  final metrics = <Metric>[
    ...?link.controller?.primary,
    ...?link.controller?.secondary,
    ...?link.bms?.primary,
    ...?link.bms?.secondary,
  ];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .55,
      maxChildSize: .92,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            [
              link.driver?.name ?? '未识别',
              link.gattInfo,
            ].where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 10),
          for (final m in metrics) MetricRow(m),
          if (link.driver?.detail.isNotEmpty ?? false) ...[
            const Divider(height: 22),
            Text(
              link.driver!.detail,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.inkSoft,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
