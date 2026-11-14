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

/// 这个名字像不像一块保护板（蚂蚁 ANT / 极空 JK 系）。
///
/// 车上两台设备是一起广播的，选控制器的列表里混着一堆 ANT-xxxx，
/// 很容易点错——点错了就是拿控制器的通道去连电池，永远出不来数。
/// 判断依据直接用保护板驱动的 nameHints，以后加品牌不用回来改这里。
bool looksLikeBmsName(String name) {
  final n = name.trim().toUpperCase();
  if (n.isEmpty) return false;
  for (final d in bmsDrivers()) {
    for (final h in d.nameHints) {
      if (n.startsWith(h.toUpperCase())) return true;
    }
  }
  return false;
}
