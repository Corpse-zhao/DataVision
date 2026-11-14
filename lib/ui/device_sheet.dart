import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/models.dart';
import '../drivers/driver.dart';
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

class _DeviceSheet extends StatefulWidget {
  final BleLink link;
  const _DeviceSheet({required this.link});

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  /// 默认只显示认识的设备；小区里的耳机、手环、共享单车锁全列出来纯属添乱
  bool _showUnknown = false;

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final isBms = link.role == 'bms';
    return SafeArea(
      child: AnimatedBuilder(
        animation: link,
        builder: (context, _) {
          final pool = isBms ? bmsDrivers() : controllerDrivers();
          final all = link.results;
          // 选控制器时把保护板排掉：蚂蚁 / 极空的广播名（ANT-xxx、JK-xxx）在车上
          // 跟控制器一起广播，混在列表里很容易点错，点错就连错通道、永远出不来数
          final byRole = isBms ? all : all.where((r) => !looksLikeBmsName(advName(r))).toList();

          bool known(ScanResult r) {
            final name = advName(r);
            // 记住过的那台永远要显示：用户可能给它改了名，或者是个我们没收录的品牌
            if (link.savedName.isNotEmpty && link.savedName == name) return true;
            return looksKnown(pool, name, servicesOf(r));
          }

          final knownList = byRole.where(known).toList();
          final hidden = byRole.length - knownList.length;
          final list = _showUnknown ? byRole : knownList;

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
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                        child: Center(
                          child: Text(
                            _emptyText(isBms: isBms, total: byRole.length, hidden: hidden),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.inkSoft, height: 1.5),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _row(context, link, pool, list[i]),
                      ),
              ),
              // 被过滤掉多少台要说清楚，否则「怎么少了一半设备」会让人以为搜不到
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已隐藏 $hidden 台未识别设备',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setState(() => _showUnknown = !_showUnknown),
                        child: Text(
                          _showUnknown ? '只看认识的' : '显示全部',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  String _emptyText({required bool isBms, required int total, required int hidden}) {
    if (total == 0) {
      // 选择控制器时一台都没有，多半是保护板被过滤掉了
      return isBms ? '还没搜到设备，确认设备已上电' : '只搜到了保护板，控制器还没上电或不在范围内';
    }
    if (hidden > 0) {
      return '搜到的 $hidden 台都不是认识的设备。\n如果是没收录的品牌，点下面「显示全部」挑一台试。';
    }
    return '还没搜到设备，确认设备已上电';
  }

  Widget _row(BuildContext context, BleLink link, List<DeviceDriver> pool, ScanResult r) {
    final name = advName(r);
    final drv = pickByName(pool, name) ?? pickByServices(pool, servicesOf(r));
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                      '${r.device.remoteId.str} · ${r.rssi} dBm',
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              if (drv != null)
                StatusPill(drv.name.split('（').first, AppColors.accent)
              else
                const StatusPill('未识别', AppColors.inkSoft),
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
  }
}

/// 广播名优先，没有就用系统名，再没有就「未知设备」
String advName(ScanResult r) {
  if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
  if (r.device.platformName.isNotEmpty) return r.device.platformName;
  return '未知设备';
}

/// 广播里带的 GATT 服务短名
List<String> servicesOf(ScanResult r) =>
    r.advertisementData.serviceUuids.map((g) => shortUuid(g.str)).toList();
