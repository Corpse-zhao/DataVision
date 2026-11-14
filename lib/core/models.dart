/// 数据视界 —— 通用数据模型
///
/// 控制器和保护板都只往界面交两类东西：
///   1. 几个「大数字」（Primary，顶部大卡片）
///   2. 一串「明细行」（Secondary）
/// 界面不认识任何具体协议，换驱动只动 drivers/ 下面的文件。
library;

enum MetricTone { normal, good, warn, bad }

class Metric {
  final String label;
  final String value;
  final String unit;
  final MetricTone tone;
  const Metric(this.label, this.value, this.unit, {this.tone = MetricTone.normal});
}

/// 控制器一帧的解读结果
class ControllerData {
  final DateTime at;
  final String? model;
  final List<Metric> primary;
  final List<Metric> secondary;
  final String? fault;
  final int frameCount;

  const ControllerData({
    required this.at,
    this.model,
    this.primary = const [],
    this.secondary = const [],
    this.fault,
    this.frameCount = 0,
  });
}

/// 保护板一帧的解读结果
class BmsData {
  final DateTime at;
  final String? brand;
  final String? model;
  final List<Metric> primary;
  final List<Metric> secondary;

  final List<double> cells; // V
  final List<double> temps; // ℃
  final int maxIdx;
  final int minIdx;
  final double maxV;
  final double minV;
  final double deltaV;
  final int soc;
  final int soh;
  final bool chargeMos;
  final bool dischargeMos;
  final bool balancer;
  final int balancingMask;
  final List<String> protection;
  final List<String> warning;

  const BmsData({
    required this.at,
    this.brand,
    this.model,
    this.primary = const [],
    this.secondary = const [],
    this.cells = const [],
    this.temps = const [],
    this.maxIdx = 0,
    this.minIdx = 0,
    this.maxV = 0,
    this.minV = 0,
    this.deltaV = 0,
    this.soc = 0,
    this.soh = 0,
    this.chargeMos = false,
    this.dischargeMos = false,
    this.balancer = false,
    this.balancingMask = 0,
    this.protection = const [],
    this.warning = const [],
  });
}

// MARK: - 数值格式化

String fmtNum(double? v, int digits) {
  if (v == null || v.isNaN || v.isInfinite) return '--';
  return v.toStringAsFixed(digits);
}

String fmtInt(int? v) => v == null ? '--' : '$v';

/// 功率：超过 1000W 换成 kW，读数更省眼睛
(String, String) fmtPower(double? w) {
  if (w == null) return ('--', 'W');
  final a = w.abs();
  if (a >= 1000) return ((w / 1000).toStringAsFixed(2), 'kW');
  return (w.toStringAsFixed(0), 'W');
}

String hex(List<int> bytes, {int max = 64}) {
  if (bytes.isEmpty) return '';
  final take = bytes.length > max ? bytes.sublist(0, max) : bytes;
  final s = take.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  return bytes.length > max ? '$s …' : s;
}

String shortUuid(String uuid) {
  final u = uuid.toUpperCase();
  if (u.length == 36 && u.startsWith('0000') && u.endsWith('-0000-1000-8000-00805F9B34FB')) {
    return u.substring(4, 8);
  }
  if (u.length == 4) return u;
  if (u.length == 8) return u;
  // 自定义 128 位：取前 8 位够认了
  return u.length > 12 ? u.substring(0, 8) : u;
}

// MARK: - 小端读取工具

int u16le(List<int> b, int o) => (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8);
int i16le(List<int> b, int o) {
  final v = u16le(b, o);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int u32le(List<int> b, int o) =>
    (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8) | ((b[o + 2] & 0xFF) << 16) | ((b[o + 3] & 0xFF) << 24);

int i32le(List<int> b, int o) {
  final v = u32le(b, o);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int u16be(List<int> b, int o) => ((b[o] & 0xFF) << 8) | (b[o + 1] & 0xFF);
int i16be(List<int> b, int o) {
  final v = u16be(b, o);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int u32be(List<int> b, int o) =>
    ((b[o] & 0xFF) << 24) | ((b[o + 1] & 0xFF) << 16) | ((b[o + 2] & 0xFF) << 8) | (b[o + 3] & 0xFF);
int i32be(List<int> b, int o) {
  final v = u32be(b, o);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}
