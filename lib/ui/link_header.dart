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

/// 空状态：没连上时给一个明显的入口，别让人对着空屏发愣。
///
/// 「连上了但没数据」也走这里 —— 那种情况最容易被误报成「连接不上」，
/// 所以按钮换成「重新连接」，再用 [note] 把现在到底收到多少字节写清楚。
class EmptyHint extends StatelessWidget {
  final BleLink link;
  final String title;
  final String subtitle;
  final IconData icon;

  /// 已经连上（只是没数据）时补的技术说明：多少字节、下一步该发我什么
  final String? note;

  /// 是否已连接：已连接就不该再让人去「搜索设备」
  final bool connected;

  const EmptyHint({
    super.key,
    required this.link,
    required this.title,
    required this.subtitle,
    this.icon = Icons.bluetooth,
    this.note,
    this.connected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      fill: true,
      // 卡片本身有整屏高度，内容要垂直居中；否则两块内容都贴顶，
      // 卡片下半截会空出一大片，看着像没渲染完
      child: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Icon(icon, size: 40, color: AppColors.inkSoft.withValues(alpha: .45)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkSoft,
                height: 1.55,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  note!,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkSoft,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (connected)
              OutlinedButton.icon(
                onPressed: () => link.reconnectNow(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新连接'),
              )
            else
              FilledButton.icon(
                onPressed: () async {
                  await link.startScan();
                  if (context.mounted) showDeviceSheet(context, link);
                },
                icon: const Icon(Icons.search, size: 18),
                label: const Text('搜索设备'),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
