import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import 'device_sheet.dart';
import 'theme.dart';

/// 两条链路共用的顶部状态条：谁连着、走的哪条信道、要不要重连
class LinkHeader extends StatelessWidget {
  final BleLink link;
  final String title;
  const LinkHeader({super.key, required this.link, required this.title});

  Color get _color {
    switch (link.phase) {
      case LinkPhase.online:
        return AppColors.good;
      case LinkPhase.connecting:
      case LinkPhase.ready:
        return AppColors.warn;
      case LinkPhase.error:
        return AppColors.bad;
      default:
        return AppColors.inkSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = link.phase == LinkPhase.online;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.deviceName.isEmpty ? title : link.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        link.status,
                        if (link.driver != null) link.driver!.name,
                        if (link.channelCount > 1)
                          '信道 ${link.channelIndex + 1}/${link.channelCount}',
                        if (online) '${link.frameCount} 帧',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              if (online)
                IconButton(
                  tooltip: '断开',
                  onPressed: () => link.disconnect(),
                  icon: Icon(
                    Icons.link_off,
                    size: 20,
                    color: AppColors.inkSoft,
                  ),
                )
              else
                IconButton(
                  tooltip: '选择设备',
                  onPressed: () async {
                    await link.startScan();
                    if (context.mounted) showDeviceSheet(context, link);
                  },
                  icon: Icon(
                    Icons.bluetooth_searching,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 空状态：没连上时给一个明显的入口，别让人对着空屏发愣
class EmptyHint extends StatelessWidget {
  final BleLink link;
  final String title;
  final String subtitle;
  final IconData icon;
  const EmptyHint({
    super.key,
    required this.link,
    required this.title,
    required this.subtitle,
    this.icon = Icons.bluetooth,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          const SizedBox(height: 18),
          Icon(icon, size: 42, color: AppColors.inkSoft.withValues(alpha: .5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await link.startScan();
              if (context.mounted) showDeviceSheet(context, link);
            },
            icon: const Icon(Icons.search, size: 18),
            label: const Text('搜索设备'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
