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

/// 白卡片：标题行 + 正文 + 通栏页脚。
/// 正文拿到的是「剩余可用高度」，由各卡片自己决定把富余塞给谁（走势图/柱形图），
/// 这样卡片不会出现整块空白，也不会因为内容放不下而溢出。
class _CardFrame extends StatelessWidget {
  final Color dot;
  final String title;
  final Widget? trailing;
  final Widget Function(double bodyH) body;
  final Widget? footer;

  const _CardFrame({
    required this.dot,
    required this.title,
    this.trailing,
    required this.body,
    this.footer,
  });

  static const _headH = 15.0;
  static const _footerH = 26.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final bodyH = math.max(
            0.0,
            box.maxHeight - _headH - 8 - (footer == null ? 0 : _footerH) - 16,
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 0),
                child: SizedBox(
                  height: _headH,
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
                  child: body(bodyH),
                ),
              ),
              if (footer != null)
                Container(
                  height: _footerH,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.line, width: .5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
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

// MARK: - 格子

class _Tile {
  final String label;
  final String value;
  final String unit;

  /// null 表示跟随主题的字色（主题是运行时切的，不能写进 const 默认值）
  final Color? color;
  final bool highlight;
  final bool small;
  const _Tile({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
    this.highlight = false,
    this.small = false,
  });

  factory _Tile.of(Metric m, {bool highlight = false, bool small = false}) =>
      _Tile(
        label: m.label,
        value: m.value,
        unit: m.unit,
        color: highlight ? AppColors.accent : AppColors.tone(m.tone),
        highlight: highlight,
        small: small,
      );
}

class _MetricGrid extends StatelessWidget {
  final List<_Tile> tiles;
  const _MetricGrid({required this.tiles});

  /// 一行固定 4 格：格子小、行数固定，横竖屏都用同一套排法
  static const cols = 4;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 6.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: w, child: _TileBox(t)),
          ],
        );
      },
    );
  }
}

class _TileBox extends StatelessWidget {
  final _Tile t;
  const _TileBox(this.t);

  @override
  Widget build(BuildContext context) {
    final labelColor = t.highlight ? AppColors.accent : AppColors.inkSoft;
    final scale = AppColors.numberScale;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: t.highlight
            ? AppColors.accent.withValues(alpha: AppColors.isDark ? .14 : .08)
            : AppColors.cardAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, height: 1.2, color: labelColor),
          ),
          const SizedBox(height: 3),
          // 窄屏（360）一行四格时 "3200rpm" 会顶出去，按比例缩而不是打省略号
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  text: t.value,
                  children: [
                    if (t.unit.isNotEmpty)
                      TextSpan(
                        text: t.unit,
                        style: TextStyle(
                          fontSize: t.small ? 10.5 : 11,
                          fontWeight: FontWeight.w500,
                          color: t.highlight
                              ? AppColors.accent.withValues(alpha: .65)
                              : AppColors.inkSoft,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                style: AppTheme.mono.copyWith(
                  fontSize: (t.small ? 13.5 : 19) * scale,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: t.color ?? AppColors.ink,
                  shadows: AppColors.numberGlow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 页脚四格：标签在上、数值在下，没有底色，视觉上比格子轻
class _FootRow extends StatelessWidget {
  final List<(String, String, String)> items; // (标签, 数值, 单位)
  const _FootRow(this.items);

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    fontSize: 10.5,
                    height: 1.1,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(
                    text: it.$2,
                    children: [
                      if (it.$3.isNotEmpty)
                        TextSpan(
                          text: it.$3,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono.copyWith(
                    fontSize: 12,
                    height: 1.0,
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

class _SectionGap extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionGap(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        const SizedBox(width: 6),
        const Expanded(child: Divider(height: 1, thickness: .5)),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
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
        _Tile.of(primary[i], highlight: i == powerIdx),
    ];
    final smallTiles = [for (final m in secondary) _Tile.of(m, small: true)];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAllMetrics(context, link, '控制器全部数据'),
      child: _CardFrame(
        dot: AppColors.accent,
        title: '${brandOf(link.driver?.name, '控制器')} · 控制器',
        trailing: Text(
          fault != null ? '故障' : (online ? '运行正常' : '等数据'),
          style: TextStyle(
            fontSize: 11,
            color: fault != null
                ? AppColors.bad
                : (online ? AppColors.good : AppColors.inkSoft),
          ),
        ),
        body: (h) {
          // 卡太扁（横屏或小屏）时，第二行指标让位给走势图
          final showSecondary = smallTiles.isNotEmpty && h > 235;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (fault != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bad.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.bad,
                      ),
                      const SizedBox(width: 5),
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
              _MetricGrid(tiles: tiles),
              if (showSecondary) _MetricGrid(tiles: smallTiles),
              // 限高 122：图不至于比格子高出一大截，剩下的余量由板块间距平均分掉
              Flexible(
                child: SizedBox(
                  height: 122,
                  child: _SparkArea(trend: trend, frames: link.frameCount),
                ),
              ),
            ],
          );
        },
        footer: Row(
          children: [
            Expanded(
              child: Text(
                '协议 ${link.driver?.name ?? '嗅探中'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ),
            Text(
              '${thousands(link.frameCount)} 帧',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
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
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: CustomPaint(
            painter: _SparkPainter(trend.values, AppColors.accent),
            child: curve
                ? null
                : Center(
                    child: Text(
                      noPowerField ? '这一路数据里没有功率，走势留空' : '跑起来几帧就出曲线',
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> pts;
  final Color color;
  _SparkPainter(this.pts, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      base,
    );
    final dashed = Paint()
      ..color = AppColors.line.withValues(alpha: .55)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      dashed,
    );

    if (pts.length < 2) return;

    var lo = pts.reduce(math.min);
    var hi = pts.reduce(math.max);
    // 一条直线（功率没变）时居中画，不要贴着底边
    final flat = hi - lo < 1;
    final pad = (hi - lo) * .12;
    lo -= pad;
    hi += pad;

    double yOf(double v) {
      if (flat) return size.height / 2;
      return size.height - 3 - (v - lo) / (hi - lo) * (size.height - 8);
    }

    final dx = size.width / (pts.length - 1);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = dx * i;
      final y = yOf(pts[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final lastX = dx * (pts.length - 1);
    canvas.drawCircle(
      Offset(lastX, yOf(pts.last)),
      2.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.pts.length != pts.length || old.color != color;
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
    final powerIdx = primary.indexWhere((m) => m.label.contains('功率'));
    final tiles = <_Tile>[
      for (var i = 0; i < primary.length && i < 4; i++)
        _Tile.of(primary[i], highlight: i == powerIdx),
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
        title: '${brandOf(link.driver?.name, '保护板')} · 保护板',
        trailing: Text(
          flagText ?? balanceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: flagText != null
                ? (data.protection.isNotEmpty ? AppColors.bad : AppColors.warn)
                : AppColors.inkSoft,
          ),
        ),
        body: (h) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MetricGrid(tiles: tiles),
            if (data.cells.isNotEmpty) ...[
              _SectionGap(
                '单体电压 · ${data.cells.length} 串',
                trailing: Text(
                  '压差 ${(data.deltaV * 1000).toStringAsFixed(0)} mV',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: data.deltaV > 0.05 ? AppColors.warn : AppColors.good,
                  ),
                ),
              ),
              // 和走势图同高（118）：两块小图比例接近，看着不会一块大一块小
              Flexible(
                child: SizedBox(height: 118, child: _CellBars(data: data)),
              ),
              _CellLegend(data: data),
            ],
            _SectionGap(
              '剩余容量',
              trailing: Text(
                remain == null
                    ? '${data.soc}%'
                    : '${remain.value} ${remain.unit} · ${data.soc}%',
                style: AppTheme.mono.copyWith(
                  fontSize: 11,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
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
        ]),
      ),
    );
  }
}

/// 一节一根柱：最高标红、最低标蓝。
/// 纯数字看不出「压差是集中还是散」，换成柱形一眼就分得出来。
class _CellBars extends StatelessWidget {
  final BmsData data;
  const _CellBars({required this.data});

  @override
  Widget build(BuildContext context) {
    final cells = data.cells;
    final lo = cells.reduce(math.min);
    final hi = cells.reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: cells.length > 24 ? .6 : 1.5,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  // 柱高最低留 30%：十六节之间常常只差十几毫伏，满量程画就全一样高了
                  heightFactor: hi - lo < 1e-9
                      ? .55
                      : .30 + .70 * ((cells[i] - lo) / (hi - lo)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: (i + 1) == data.maxIdx
                          ? AppColors.bad
                          : (i + 1) == data.minIdx
                          ? AppColors.cool
                          : AppColors.barIdle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
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
    return Row(
      children: [
        Expanded(
          child: Text(
            '#${data.minIdx} 最低 ${data.minV.toStringAsFixed(3)}V',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.cool),
          ),
        ),
        Text(
          '平均 ${avg.toStringAsFixed(3)}V',
          style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
        ),
        Expanded(
          child: Text(
            '#${data.maxIdx} 最高 ${data.maxV.toStringAsFixed(3)}V',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.bad),
          ),
        ),
      ],
    );
  }
}

class _SocBar extends StatelessWidget {
  final int soc;
  const _SocBar({required this.soc});

  @override
  Widget build(BuildContext context) {
    final value = (soc.clamp(0, 100)) / 100.0;
    final color = soc < 20
        ? AppColors.bad
        : (soc < 50 ? AppColors.warn : AppColors.good);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: AppColors.line,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: ColoredBox(color: color),
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
