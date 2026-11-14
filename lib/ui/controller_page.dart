import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/models.dart';
import 'link_header.dart';
import 'theme.dart';

class ControllerPage extends StatelessWidget {
  final BleLink link;
  const ControllerPage({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: link,
      builder: (context, _) {
        final data = link.controller;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            LinkHeader(link: link, title: '控制器'),
            const SizedBox(height: 12),
            if (data == null)
              EmptyHint(
                link: link,
                icon: Icons.memory,
                title: link.phase == LinkPhase.online ? '已连上，等第一帧' : '还没连控制器',
                subtitle: '支持凌博、远驱（Fardriver / VOTOL / YuanQu）、VESC 系'
                    '（Flipsky / MakerX / Trampa 等）。\n第一次手动选一下，以后自动连。',
              )
            else ...[
              _PrimaryGrid(metrics: data.primary),
              if (data.fault != null) ...[
                const SizedBox(height: 12),
                _FaultBanner(text: data.fault!),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: '明细',
                child: Column(
                  children: [
                    for (final m in data.secondary) MetricRow(m),
                  ],
                ),
              ),
              if (link.driver?.detail.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: '协议状态',
                  child: Text(link.driver!.detail,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.6)),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _PrimaryGrid extends StatelessWidget {
  final List<Metric> metrics;
  const _PrimaryGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cols = w > 560 ? 4 : 2;
      const gap = 10.0;
      final itemW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final m in metrics)
            SizedBox(width: itemW, height: 88, child: BigTile(m)),
        ],
      );
    });
  }
}

class _FaultBanner extends StatelessWidget {
  final String text;
  const _FaultBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bad.withValues(alpha: .07),
        border: Border.all(color: AppColors.bad.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.bad, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.bad, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
