import 'package:material_ui/material_ui.dart';

import '../core/models.dart';

/// 配色：浅色底 + 纯白卡片，数字用等宽字体，白天强光下也读得清。
class AppColors {
  static const bg = Color(0xFFF2F4F7);
  static const card = Colors.white;
  static const ink = Color(0xFF14181F);
  static const inkSoft = Color(0xFF6B7280);
  static const line = Color(0xFFE6E9EF);

  static const accent = Color(0xFF2563EB); // 主蓝
  static const good = Color(0xFF16A34A);
  static const warn = Color(0xFFD97706);
  static const bad = Color(0xFFDC2626);
  static const cool = Color(0xFF0EA5E9);

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
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        surface: AppColors.card,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'Microsoft YaHei',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      dividerColor: AppColors.line,
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static const mono = TextStyle(
    fontFamily: 'Consolas',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
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
                    child: Text(title!,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSoft,
                            letterSpacing: .3)),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
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
                    fontSize: 30,
                    height: 1.0,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (metric.unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(metric.unit,
                      style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
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
            child: Text(metric.label,
                style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
          Text(
            metric.value,
            style: AppTheme.mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
          if (metric.unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(metric.unit,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
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
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}
