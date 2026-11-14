import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/models.dart';
import 'link_header.dart';
import 'theme.dart';

class BmsPage extends StatelessWidget {
  final BleLink link;
  const BmsPage({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: link,
      builder: (context, _) {
        final data = link.bms;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            LinkHeader(link: link, title: '保护板'),
            const SizedBox(height: 12),
            if (data == null)
              EmptyHint(
                link: link,
                icon: Icons.battery_std,
                title: link.phase == LinkPhase.online ? '已连上，等第一帧' : '还没连保护板',
                subtitle: '支持蚂蚁（ANT）和极空（JK）。\n蚂蚁板有三条信道，第一条不通会自动换第二条、第三条。',
              )
            else ...[
              _PrimaryRow(metrics: data.primary, soc: data.soc),
              const SizedBox(height: 12),
              if (data.protection.isNotEmpty || data.warning.isNotEmpty)
                _FlagCard(protection: data.protection, warning: data.warning),
              if (data.protection.isNotEmpty || data.warning.isNotEmpty) const SizedBox(height: 12),
              if (data.cells.isNotEmpty) ...[
                _CellsCard(data: data),
                const SizedBox(height: 12),
              ],
              SectionCard(
                title: '明细',
                child: Column(
                  children: [
                    for (final m in data.secondary) MetricRow(m),
                  ],
                ),
              ),
              if (data.temps.isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: '温度探头',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < data.temps.length; i++)
                        StatusPill(
                          'T${i + 1}  ${data.temps[i].toStringAsFixed(0)}℃',
                          data.temps[i] > 55 ? AppColors.warn : AppColors.cool,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: 'MOS 状态',
                child: Row(
                  children: [
                    _MosChip('充电', data.chargeMos),
                    const SizedBox(width: 8),
                    _MosChip('放电', data.dischargeMos),
                    const SizedBox(width: 8),
                    _MosChip('均衡', data.balancer),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PrimaryRow extends StatelessWidget {
  final List<Metric> metrics;
  final int soc;
  const _PrimaryRow({required this.metrics, required this.soc});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cols = w > 560 ? 4 : 2;
      const gap = 10.0;
      final itemW = (w - gap * (cols - 1)) / cols;
      return Column(
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final m in metrics) SizedBox(width: itemW, height: 88, child: BigTile(m)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('SOC', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (soc.clamp(0, 100)) / 100.0,
                      minHeight: 8,
                      backgroundColor: AppColors.line,
                      valueColor: AlwaysStoppedAnimation(
                        soc < 20 ? AppColors.bad : (soc < 50 ? AppColors.warn : AppColors.good),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$soc%',
                    style: AppTheme.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _CellsCard extends StatelessWidget {
  final BmsData data;
  const _CellsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '单体电压（${data.cells.length}S）',
      trailing: Text(
        '压差 ${(data.deltaV * 1000).toStringAsFixed(0)} mV',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: data.deltaV > 0.05 ? AppColors.warn : AppColors.good,
        ),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 8 : (box.maxWidth > 380 ? 6 : 4);
        const gap = 6.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < data.cells.length; i++)
              _CellChip(
                index: i + 1,
                volts: data.cells[i],
                width: w,
                isMax: i + 1 == data.maxIdx,
                isMin: i + 1 == data.minIdx,
                balancing: (data.balancingMask >> i) & 1 == 1,
              ),
          ],
        );
      }),
    );
  }
}

class _CellChip extends StatelessWidget {
  final int index;
  final double volts;
  final double width;
  final bool isMax;
  final bool isMin;
  final bool balancing;
  const _CellChip({
    required this.index,
    required this.volts,
    required this.width,
    required this.isMax,
    required this.isMin,
    required this.balancing,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMax
        ? AppColors.bad
        : isMin
            ? AppColors.cool
            : AppColors.ink;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isMax
            ? AppColors.bad.withValues(alpha: .06)
            : isMin
                ? AppColors.cool.withValues(alpha: .06)
                : AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: balancing
              ? AppColors.good.withValues(alpha: .6)
              : (isMax || isMin ? color.withValues(alpha: .25) : AppColors.line),
          width: balancing ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Text('$index', style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
          const SizedBox(height: 1),
          FittedBox(
            child: Text(
              (volts * 1000).toStringAsFixed(0),
              style: AppTheme.mono.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final List<String> protection;
  final List<String> warning;
  const _FlagCard({required this.protection, required this.warning});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '保护 / 告警',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in protection) StatusPill(p, AppColors.bad, filled: true),
          for (final w in warning) StatusPill(w, AppColors.warn),
        ],
      ),
    );
  }
}

class _MosChip extends StatelessWidget {
  final String label;
  final bool on;
  const _MosChip(this.label, this.on);

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      '$label ${on ? '开' : '关'}',
      on ? AppColors.good : AppColors.inkSoft,
      filled: on,
    );
  }
}
