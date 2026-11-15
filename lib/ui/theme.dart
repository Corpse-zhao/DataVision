import 'package:material_ui/material_ui.dart';

import '../core/models.dart';

/// 背景装饰。都是"氛围"，alpha 一律压得很低，绝不能和数据抢注意力。
enum Deco {
  none,
  grid, // 方格纸
  dots, // 点阵
  scan, // CRT 扫描线
}

/// 一套主题 = 一组颜色 + 几个造型参数。
///
/// 只放「换主题要跟着变」的东西：底色、卡片色、字色、四种语义色，外加圆角、
/// 数字缩放、发光、背景装饰。字号排布、留白这些不算主题，各页自己定，
/// 免得换主题把版式也换乱了。
///
/// 渐变相关的字段全是可选的：给 null 就退回纯色，老主题一行都不用改。
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
  final Deco deco;

  /// 页面底色渐变（纵向）。给了就把 appBar / 底栏也一起对上，接缝看不出来。
  final List<Color>? bgGrad;

  /// 主色渐变：主数值、走势线用它上色
  final List<Color>? accentGrad;

  /// 卡片自身的纵向渐变（上浅下深，让卡片有点"厚度"）
  final Color? cardTop;
  final Color? cardBottom;

  /// 卡片描边渐变。给了就是一圈双色"霓虹边"，比一根灰线花哨得多
  final List<Color>? borderGrad;

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
    this.deco = Deco.none,
    this.bgGrad,
    this.accentGrad,
    this.cardTop,
    this.cardBottom,
    this.borderGrad,
  });

  /// 有没有背景装饰（老代码按 grid 判断，保留这个读法）
  bool get grid => deco != Deco.none;

  /// 顶栏/状态栏那一圈该用什么颜色：有渐变就跟渐变的第一格对齐
  Color get chrome => bgGrad?.first ?? bg;

  /// 底部导航：跟渐变的最后一格对齐，页面就"长"到底了
  Color get navSurface => bgGrad?.last ?? card;
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
    deco: Deco.grid,
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
    deco: Deco.grid,
  );

  /// 5. 强光：纯白 + 纯黑描边 + 直角 + 更大的黑字，像电子墨水屏。
  /// 它和「浅色」的区别不在颜色，而在**版式质感**：浅色是柔和的灰底白卡圆角，
  /// 强光是硬黑边框、方角、数字全黑、字号放大——太阳底下要的是对比度不是美观。
  static const stronglight = AppPalette(
    id: 'stronglight',
    name: '强光',
    desc: '纯白黑边直角，正午太阳底下最硬',
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF4F4F4),
    ink: Color(0xFF000000),
    inkSoft: Color(0xFF3C3C3C),
    line: Color(0xFF1A1A1A),
    accent: Color(0xFF000000),
    good: Color(0xFF00662B),
    warn: Color(0xFF8A4A00),
    bad: Color(0xFFB00020),
    cool: Color(0xFF00377A),
    barIdle: Color(0xFF8A8A8A),
    radius: 3,
    numberScale: 1.2,
  );

  /// 6. 霓虹：深紫底 + 品红/青双色，卡片一圈渐变描边，CRT 扫描线
  static const neon = AppPalette(
    id: 'neon',
    name: '霓虹',
    desc: '深紫底、品红配青，卡片描边会发光',
    brightness: Brightness.dark,
    bg: Color(0xFF14002B),
    bgGrad: [Color(0xFF22003F), Color(0xFF12002A), Color(0xFF070016)],
    card: Color(0xFF1B0A34),
    cardTop: Color(0xFF24113F),
    cardBottom: Color(0xFF140726),
    cardAlt: Color(0xFF210D3C),
    ink: Color(0xFFF7EEFF),
    inkSoft: Color(0xFFA98BC7),
    line: Color(0xFF3B2362),
    accent: Color(0xFFFF2FB9),
    accentGrad: [Color(0xFFFF2FB9), Color(0xFF9B5BFF), Color(0xFF2FE8FF)],
    borderGrad: [Color(0xFFFF2FB9), Color(0xFF2FE8FF)],
    good: Color(0xFF2FE8C0),
    warn: Color(0xFFFFC24B),
    bad: Color(0xFFFF4D6D),
    cool: Color(0xFF2FE8FF),
    barIdle: Color(0xFF412C6B),
    radius: 18,
    numberScale: 1.02,
    glow: true,
    deco: Deco.scan,
  );

  /// 7. 极光：墨绿底泛青紫，数字是青→蓝→紫的渐变
  static const aurora = AppPalette(
    id: 'aurora',
    name: '极光',
    desc: '墨绿底泛青紫，数字自带渐变色',
    brightness: Brightness.dark,
    bg: Color(0xFF04141A),
    bgGrad: [Color(0xFF07282F), Color(0xFF06191F), Color(0xFF08121F)],
    card: Color(0xFF0A2129),
    cardTop: Color(0xFF0E2C36),
    cardBottom: Color(0xFF081A21),
    cardAlt: Color(0xFF0F2A33),
    ink: Color(0xFFEAFBF6),
    inkSoft: Color(0xFF7FA6A6),
    line: Color(0xFF1D3E44),
    accent: Color(0xFF5BFFC4),
    accentGrad: [Color(0xFF5BFFC4), Color(0xFF5BD8FF), Color(0xFF9B8BFF)],
    good: Color(0xFF5BFFC4),
    warn: Color(0xFFFFD166),
    bad: Color(0xFFFF5C7A),
    cool: Color(0xFF5BD8FF),
    barIdle: Color(0xFF23565C),
    radius: 14,
    numberScale: 1.02,
    glow: true,
    deco: Deco.dots,
  );

  /// 8. 糖果：浅色里花哨的那一个 —— 粉蓝渐变底、粉紫渐变数字、大圆角
  static const candy = AppPalette(
    id: 'candy',
    name: '糖果',
    desc: '粉蓝渐变底，数字是粉紫渐变',
    brightness: Brightness.light,
    bg: Color(0xFFFAF3FA),
    bgGrad: [Color(0xFFFDEFF8), Color(0xFFF4EFFF), Color(0xFFEAF4FF)],
    card: Color(0xFFFFFFFF),
    cardTop: Color(0xFFFFFFFF),
    cardBottom: Color(0xFFFBF7FF),
    cardAlt: Color(0xFFF6F1FE),
    ink: Color(0xFF231B2F),
    inkSoft: Color(0xFF7A6E8C),
    line: Color(0xFFEADFF5),
    accent: Color(0xFFE01F7A),
    accentGrad: [Color(0xFFE01F7A), Color(0xFFA03BE0), Color(0xFF8B4BFF)],
    good: Color(0xFF0E9F6E),
    warn: Color(0xFFD97706),
    bad: Color(0xFFE11D48),
    // 纯正的宝蓝压在粉紫页面上太跳，换成偏紫的蓝
    cool: Color(0xFF6B5BFF),
    barIdle: Color(0xFFDCCBF0),
    radius: 20,
    deco: Deco.dots,
  );

  static const all = <AppPalette>[
    classic,
    stronglight,
    candy,
    midnight,
    hud,
    amber,
    neon,
    aurora,
  ];

  static AppPalette byId(String? id) {
    // 老的「强光」被重做过一版（id 一起换了），老用户的选择要接得上
    final key = id == 'daylight' ? stronglight.id : id;
    return all.firstWhere((p) => p.id == key, orElse: () => classic);
  }
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
  static Deco get deco => _p.deco;
  static bool get isDark => _p.brightness == Brightness.dark;

  static List<Color>? get bgGrad => _p.bgGrad;
  static List<Color>? get accentGrad => _p.accentGrad;
  static Color get chrome => _p.chrome;
  static Color get navSurface => _p.navSurface;

  /// 细线：分隔线、图表基线。比 line 再淡一档，避免版面被横线切碎
  static Color get hairline => _p.line.withValues(alpha: isDark ? .85 : .75);

  /// 图表网格线，只用在图里
  static Color get gridLine => _p.line.withValues(alpha: isDark ? .55 : .5);

  /// 卡片外观。有渐变底色就用渐变，有描边渐变就用双色霓虹边，否则退回一根细灰线。
  ///
  /// [color] 用于"另铺一层底色"的场合（页脚、指标条），此时一律纯色不渐变。
  static BoxDecoration cardBox({Color? color, double? radius}) {
    final r = radius ?? _p.radius;
    final useGrad = color == null && _p.cardTop != null;
    final grad = _p.borderGrad;
    return BoxDecoration(
      color: useGrad ? null : (color ?? _p.card),
      gradient: useGrad
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_p.cardTop!, _p.cardBottom ?? _p.cardTop!],
            )
          : null,
      borderRadius: BorderRadius.circular(r),
      border: grad == null
          ? Border.all(color: hairline)
          : GradientBorder(colors: grad, width: 1, radius: r),
    );
  }

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
        // 顶栏要跟背景渐变的起点对齐，否则顶上会出一条明显的分界
        backgroundColor: p.chrome,
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
        backgroundColor: p.navSurface,
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

/// 双色描边。BoxDecoration 自带不了渐变边框，只能自己实现一个 BoxBorder：
/// 用渐变 shader 沿圆角路径描一圈。
class GradientBorder extends BoxBorder {
  final List<Color> colors;
  final double width;
  final double radius;
  const GradientBorder({
    required this.colors,
    this.width = 1,
    this.radius = 14,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  bool get isUniform => true;

  @override
  BorderSide get top => BorderSide(color: colors.first, width: width);

  @override
  BorderSide get bottom => BorderSide(color: colors.last, width: width);

  @override
  GradientBorder scale(double t) =>
      GradientBorder(colors: colors, width: width * t, radius: radius * t);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final br = borderRadius ?? BorderRadius.circular(radius);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawRRect(br.toRRect(rect).deflate(width / 2), paint);
  }
}

/// 渐变文字。给主数值用：同一行数字从左到右换色，比纯色多一层"电子的味道"。
///
/// 注意它内部会 saveLayer，外面的 blur 阴影会被这一层裁掉，
/// 所以渐变数字不要挂大半径阴影 —— 要光晕的话在背后垫一层径向渐变。
class GradientText extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final bool horizontal;
  const GradientText({
    super.key,
    required this.child,
    required this.colors,
    this.horizontal = true,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: colors,
      ).createShader(rect),
      child: child,
    );
  }
}

/// 背景板：渐变底 + 装饰纹。只负责"氛围"，不拦点击，也不放任何数据。
class ThemeBackdrop extends StatelessWidget {
  final Widget child;
  const ThemeBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final grad = AppColors.bgGrad;
    final deco = AppColors.deco;
    // 纯色 + 无装饰就直接放行，省一层 Stack
    if (grad == null && deco == Deco.none) return child;
    return Stack(
      children: [
        if (grad != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: grad,
                ),
              ),
            ),
          ),
        if (deco != Deco.none)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DecoPainter(
                  deco,
                  AppColors.line.withValues(alpha: deco == Deco.scan ? .16 : .22),
                  AppColors.accent.withValues(alpha: .10),
                ),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _DecoPainter extends CustomPainter {
  final Deco deco;
  final Color color;
  final Color tint;
  _DecoPainter(this.deco, this.color, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = .8;
    switch (deco) {
      case Deco.grid:
        const step = 32.0;
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case Deco.dots:
        const gap = 24.0;
        final dot = Paint()..color = color;
        for (var y = gap; y < size.height; y += gap) {
          for (var x = gap; x < size.width; x += gap) {
            canvas.drawCircle(Offset(x, y), 1.1, dot);
          }
        }
      case Deco.scan:
        // CRT 扫描线：4px 一道，极淡；再在顶部压一层主色光带
        for (var y = 0.0; y < size.height; y += 4) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height * .35),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tint, tint.withValues(alpha: 0)],
            ).createShader(
              Rect.fromLTWH(0, 0, size.width, size.height * .35),
            ),
        );
      case Deco.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_DecoPainter old) =>
      old.deco != deco || old.color != color || old.tint != tint;
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
      decoration: AppColors.cardBox(),
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
      decoration: AppColors.cardBox(),
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
