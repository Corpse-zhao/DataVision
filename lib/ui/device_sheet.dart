import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/models.dart';
import '../drivers/registry.dart';
import 'theme.dart';

/// 选设备面板：第一次用的时候在这里点一下，之后就不用再来了。
Future<void> showDeviceSheet(BuildContext context, BleLink link) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _DeviceSheet(link: link),
  );
}

class _DeviceSheet extends StatelessWidget {
  final BleLink link;
  const _DeviceSheet({required this.link});

  @override
  Widget build(BuildContext context) {
    final isBms = link.role == 'bms';
    return SafeArea(
      child: AnimatedBuilder(
        animation: link,
        builder: (context, _) {
          final pool = isBms ? bmsDrivers() : controllerDrivers();
          final list = link.results;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isBms ? '选择保护板' : '选择控制器',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => link.startScan(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重新搜索'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppColors.inkSoft),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '第一次选好之后会自动记住，以后搜到就自己连',
                        style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('还没搜到设备，确认设备已上电', style: TextStyle(color: AppColors.inkSoft)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = list[i];
                          final name = r.advertisementData.advName.isNotEmpty
                              ? r.advertisementData.advName
                              : (r.device.platformName.isEmpty ? '未知设备' : r.device.platformName);
                          final adv = r.advertisementData.serviceUuids.map((g) => g.str).toList();
                          final drv = pickByName(pool, name) ?? pickByServices(pool, adv.map(shortUuid).toList());
                          final saved = link.savedName.isNotEmpty && link.savedName == name;
                          return Material(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.of(context).pop();
                                link.connectDevice(r.device);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 15, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${r.device.remoteId.str} · ${r.rssi} dBm',
                                            style: const TextStyle(
                                                fontSize: 11, color: AppColors.inkSoft),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (drv != null)
                                      StatusPill(drv.name.split('（').first,
                                          AppColors.accent),
                                    if (saved)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: StatusPill('已记住', AppColors.good),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }
}
