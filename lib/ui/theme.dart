import 'package:material_ui/material_ui.dart';

import '../core/models.dart';

/// 一套主题 = 一组颜色 + 几个造型参数。
///
/// 只放「换主题要跟着变」的东西：底色、卡片色、字色、四种语义色，外加圆角、
/// 数字缩放、发光、背景网格。字号排布、留白这些不算主题，各页自己定，
/// 免得换主题把版式也换乱了。
class AppPalette {
  final String id;
  final String name;
  final String desc;
  final Brightness brightness;

  final Color bg;
  final Color card;
  final Color cardAlt; // 格子/内嵌块的底
  final Color ink;
  final Color inkSoft;
  final Color line;

  final Color accent;
  final Color good;
  final Color warn;
  final Color bad;
  final Color cool;
  final Color barIdle; // 单体电压柱的常态色

  final double radius;
  final double numberScale; // 数字字号倍数（强光/车载主题放大一点）
  final bool glow; // 数字带光晕
  final bool grid; // 背景细网格

  const AppPalette({
    required this.id,
    required this.name,
    required this.desc,
    required this.brightness,
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.accent,
    required this.good,
    required this.warn,
    required this.bad,
    required this.cool,
    required this.barIdle,
    this.radius = 14,
    this.numberScale = 1.0,
    this.glow = false,
    this.grid = false,
  });
}

class AppPalettes {
  /// 1. 浅色经典：原来的白底蓝字，白天室内最舒服
  static const classic = AppPalette(
    id: 'classic',
    name: '浅色',
    desc: '白底纸感，室内看得最清',
    brightness: Brightness.light,
    bg: Color(0xFFEFF2F6),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF3F6FA),
    ink: Color(0xFF11161D),
    inkSoft: Color(0xFF6A7280),
    line: Color(0xFFE4E8EF),
    accent: Color(0xFF2563EB),
    good: Color(0xFF16A34A),
    warn: Color(0xFFD97706),
    bad: Color(0xFFDC2626),
    cool: Color(0xFF0EA5E9),
    barIdle: Color(0xFFC6D4E6),
    radius: 14,
  );

  /// 2. 夜色：深蓝黑底，夜里不刺眼，蓝作主色
  static const midnight = AppPalette(
    id: 'midnight',
    name: '夜色',
    desc: '深蓝黑底，晚上开着不晃眼',
    brightness: Brightness.dark,
    bg: Color(0xFF080C10),
    card: Color(0xFF141C25),
    cardAlt: Color(0xFF0E151D),
    ink: Color(0xFFEAF1F8),
    inkSoft: Color(0xFF8FA1B4),
    line: Color(0xFF25313D),
    accent: Color(0xFF3E8BFF),
    good: Color(0xFF35D07F),
    warn: Color(0xFFF5A524),
    bad: Color(0xFFFF5A5F),
    cool: Color(0xFF47C7FF),
    barIdle: Color(0xFF33465A),
    radius: 16,
  );

  /// 3. 车载 HUD：纯黑底 + 荧光青绿，数字带光晕、背景细网格
  static const hud = AppPalette(
    id: 'hud',
    name: 'HUD',
    desc: '纯黑底荧光青，强光下也跳出来',
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    card: Color(0xFF0A0F11),
    cardAlt: Color(0xFF111A1C),
    ink: Color(0xFFF2F7F6),
    inkSoft: Color(0xFF8A9B9D),
    line: Color(0xFF1F2A2C),
    accent: Color(0xFF00E5A0),
    good: Color(0xFF22E06B),
    warn: Color(0xFFFFC24B),
    bad: Color(0xFFFF4D4D),
    cool: Color(0xFF23D3FF),
    barIdle: Color(0xFF2C3D3F),
    radius: 10,
    numberScale: 1.06,
    glow: true,
    grid: true,
  );

  /// 4. 琥珀：老仪表盘的暖光，长途夜骑最耐看
  static const amber = AppPalette(
    id: 'amber',
    name: '琥珀',
    desc: '暖光仪表盘，夜里看着不累',
    brightness: Brightness.dark,
    bg: Color(0xFF0D0906),
    card: Color(0xFF1B1309),
    cardAlt: Color(0xFF241A0C),
    ink: Color(0xFFFFEFD6),
    inkSoft: Color(0xFFAE8F63),
    line: Color(0xFF332817),
    accent: Color(0xFFFFA71F),
    good: Color(0xFFFFC24D),
    warn: Color(0xFFFF8A00),
    bad: Color(0xFFFF4D3D),
    cool: Color(0xFFFFD98A),
    barIdle: Color(0xFF4A3820),
    radius: 8,
    numberScale: 1.06,
    glow: true,
    grid: true,
  );

  /// 5. 强光：接近纯白 + 纯黑字 + 大一号数字，正午太阳下用
  static const daylight = AppPalette(
    id: 'daylight',
    name: '强光',
    desc: '又黑又大的字，太阳底下也读得清',
    brightness: Brightness.light,
    bg: Color(0xFFEDF0F3),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFE9EDF1),
    ink: Color(0xFF000000),
    inkSoft: Color(0xFF3C444C),
    line: Color(0xFFC9D0D8),
    accent: Color(0xFF0B5FFF),
    good: Color(0xFF067647),
    warn: Color(0xFF9A4A00),
    bad: Color(0xFFB00020),
    cool: Color(0xFF026AA2),
    barIdle: Color(0xFFB9C3CE),
    radius: 8,
    numberScale: 1.14,
  );

  static const all = <AppPalette>[classic, midnight, hud, amber, daylight];

  static AppPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => classic);
}

/// 当前主题。整个 App 只有这一个可变点，改完 notify 就从根上重建。
class AppThemeManager extends ChangeNotifier {
  static final AppThemeManager instance = AppThemeManager._();
  AppThemeManager._();

  AppPalette _palette = AppPalettes.classic;
  AppPalette get palette => _palette;
  String get id => _palette.id;

  /// 启动时恢复；同一个 id 不重复通知，避免开机白重建一次
  void restore(String? id) {
    final next = AppPalettes.byId(id);
    if (next.id == _palette.id) return;
    _palette = next;
    notifyListeners();
  }

  void select(String id) => restore(id);
}

/// 颜色门面。全项目都写 `AppColors.ink` 这种，换主题时不用改任何调用点。
///
/// 注意：这些是 getter 不是 const，凡是放进 `const TextStyle(...)` 的地方
/// 都必须去掉 const。
class AppColors {
  static AppPalette get _p => AppThemeManager.instance.palette;

  static Color get bg => _p.bg;
  static Color get card => _p.card;
  static Color get cardAlt => _p.cardAlt;
  static Color get ink => _p.ink;
  static Color get inkSoft => _p.inkSoft;
  static Color get line => _p.line;

  static Color get accent => _p.accent;
  static Color get good => _p.good;
  static Color get warn => _p.warn;
  static Color get bad => _p.bad;
  static Color get cool => _p.cool;
  static Color get barIdle => _p.barIdle;

  static double get radius => _p.radius;
  static double get numberScale => _p.numberScale;
  static bool get glow => _p.glow;
  static bool get grid => _p.grid;
  static bool get isDark => _p.brightness == Brightness.dark;

  /// 细线：分隔线、图表基线。比 line 再淡一档，避免版面被横线切碎
  static Color get hairline => _p.line.withValues(alpha: isDark ? .85 : .75);

  /// 图表网格线，只用在图里
  static Color get gridLine => _p.line.withValues(alpha: isDark ? .55 : .5);

  /// 数字光晕（只有 HUD / 琥珀这类主题给）。
  ///
  /// [strong] 只给主数值 —— 一屏八个数字全都发光等于都不发光。
  static List<Shadow>? glowFor({bool strong = false}) {
    if (!_p.glow) return null;
    return [
      Shadow(
        color: _p.accent.withValues(alpha: strong ? .45 : .22),
        blurRadius: strong ? 16 : 8,
      ),
    ];
  }

  /// 兼容老调用点
  static List<Shadow>? get numberGlow => glowFor();

  static Color tone(MetricTone t) {
    switch (t) {
      case MetricTone.good:
        return good;
      case MetricTone.warn:
        return warn;
      case MetricTone.bad:
        return bad;
      default:
        return ink;
    }
  }
}

class AppTheme {
  static ThemeData of(AppPalette p) {
    final dark = p.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.brightness,
        surface: p.card,
      ),
      scaffoldBackgroundColor: p.bg,
      fontFamily: 'Microsoft YaHei',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
      dividerColor: p.line,
      canvasColor: p.bg,
      cardColor: p.card,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.line,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accent.withValues(alpha: dark ? .18 : .10),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, color: p.inkSoft),
        ),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: p.inkSoft)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? p.cardAlt : const Color(0xFF1F2937),
        contentTextStyle: TextStyle(
          color: dark ? p.ink : Colors.white,
          fontSize: 13,
        ),
        actionTextColor: p.accent,
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.card),
      dividerTheme: DividerThemeData(color: p.line, thickness: .6),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      iconTheme: IconThemeData(color: p.inkSoft),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.accent.withValues(alpha: .40)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        thumbColor: p.accent,
        inactiveTrackColor: p.line,
      ),
    );
  }

  /// 数字样式：等宽数字 + 跟随主题字体。
  ///
  /// 特意不指定 'Consolas'：App 不内嵌字体，这个族名在 iOS/Android 上根本不存在，
  /// 写了也只是"看起来配了"。反而在桌面/测试环境里它会真的生效，而 Consolas 的零
  /// 带一道斜杠（60.3 会读成 6Ø.3），在数字为主的界面上是硬伤。
  /// [FontFeature.tabularFigures] 才是这里真正想要的东西：每个数字等宽，跳数不抖。
  static const mono = TextStyle(
    fontFamilyFallback: ['Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC'],
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 背景网格：只给车载/HUD 主题用，画一层极淡的格子，让纯黑底不那么"空"。
///
/// 放在 Scaffold 之上、内容之下，不拦点击。alpha 压得很低（.22）—— 网格是氛围，
/// 一旦能看清楚就会和数据抢注意力，卡片边缘也会显得毛糙。
class ThemeBackdrop extends StatelessWidget {
  final Widget child;
  const ThemeBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!AppColors.grid) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GridPainter(AppColors.line.withValues(alpha: .22)),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = .8;
    const step = 32.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  /// true = 内容纵向撑满卡片。Column 给子项的是「无界高度」，
  /// 直接放 Align/Center 是居中不了的，必须走 Expanded 才会真的占满。
  final bool fill;

  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

/// 顶部大数字
class BigTile extends StatelessWidget {
  final Metric metric;
  const BigTile(this.metric, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.tone(metric.tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono.copyWith(
                    fontSize: 30 * AppColors.numberScale,
                    height: 1.0,
                    fontWeight: FontWeight.w600,
                    color: color,
                    shadows: AppColors.numberGlow,
                  ),
                ),
              ),
              if (metric.unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    metric.unit,
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 明细行
class MetricRow extends StatelessWidget {
  final Metric metric;
  const MetricRow(this.metric, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.tone(metric.tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.label,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
          Text(
            metric.value,
            style: AppTheme.mono.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (metric.unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                metric.unit,
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const StatusPill(this.text, this.color, {super.key, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : .25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: filled
              ? (AppColors.isDark ? AppColors.bg : Colors.white)
              : color,
        ),
      ),
    );
  }
}
