import 'driver.dart';
import 'ant_bms.dart';
import 'fardriver.dart';
import 'jk_bms.dart';
import 'lingbo.dart';
import 'vesc.dart';

/// 控制器候选驱动。顺序 = 嗅探顺序（认不出来时按这个顺序试）。
List<DeviceDriver> controllerDrivers() => [LingboDriver(), FardriverDriver(), VescDriver()];

/// 保护板候选驱动。蚂蚁在前：市面上蚂蚁板最多，且它的帧头 7EA1 不会和极空撞。
List<DeviceDriver> bmsDrivers() => [AntBmsDriver(), JkBmsDriver()];

/// 广播名 → 驱动
DeviceDriver? pickByName(List<DeviceDriver> pool, String name) {
  final n = name.toUpperCase();
  if (n.isEmpty) return null;
  for (final d in pool) {
    for (final h in d.nameHints) {
      if (n.contains(h)) return d;
    }
  }
  return null;
}

/// GATT 服务短名 → 驱动
DeviceDriver? pickByServices(List<DeviceDriver> pool, List<String> services) {
  for (final d in pool) {
    for (final h in d.serviceHints) {
      if (services.contains(h)) return d;
    }
  }
  return null;
}
