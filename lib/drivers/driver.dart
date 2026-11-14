import '../core/models.dart';

enum DriverKind { controller, bms }

/// 所有协议驱动的共同门面。
///
/// 传输层（ble/link.dart）只认这五个方法，驱动内部怎么拆帧、怎么换算都不关它的事。
/// 加一个新品牌 = 新建一个文件实现这个类，再在 [driversFor] 里注册一行。
abstract class DeviceDriver {
  String get id;
  String get name;
  DriverKind get kind;

  /// 广播名关键字（大写，包含即算）。用来在扫描列表里把它排前面。
  List<String> get nameHints;

  /// 广播包 / GATT 里出现这些服务短名就认为是它（'FFE0'、'6E400001' 这类）
  List<String> get serviceHints;

  /// 通知通道提示（只用于排序，实际会订阅所有可通知特征）
  List<String> get notifyHints;

  /// 写入信道提示，**顺序即优先级**：第一条不通试第二条，再不通试第三条
  List<String> get writeHints;

  int get pollIntervalMs => 400;

  /// 多久没收到帧就当成「假在线」（换信道 / 重连）。
  /// 慢速协议调大一点：蚂蚁板一帧 152 字节要分 8 包通知上来，
  /// 掉一包就得等下一轮，6 秒太紧，会误判成断线然后主动重连，越重连越没数据。
  static const defaultStaleSeconds = 6;
  int get staleTimeoutSeconds => defaultStaleSeconds;

  /// 被动型（远驱）：连上就自己推，不发请求
  bool get passive => false;

  /// 建立订阅后发一次的帧
  List<List<int>> get initialFrames => const [];

  /// 每一轮轮询要发的帧，tick 从 0 开始递增
  List<List<int>> pollFrames(int tick) => const [];

  /// 喂一段收到的字节；解析出完整一帧返回 true
  bool feed(List<int> chunk);

  void reset();

  ControllerData? get controllerData => null;
  BmsData? get bmsData => null;

  /// 最近一帧原始字节（数据台用）
  List<int> get lastFrame => const [];

  /// 数据台里显示的驱动内部状态（标定分母、极对数之类）
  String get detail => '';
}

/// 认不出来的设备用这个兜底：不解析、不发请求，只让用户在数据台看原始字节。
class RawDriver extends DeviceDriver {
  @override
  String get id => 'raw';
  @override
  String get name => '未识别设备（只看原始数据）';
  @override
  DriverKind get kind => DriverKind.controller;
  @override
  List<String> get nameHints => const [];
  @override
  List<String> get serviceHints => const [];
  @override
  List<String> get notifyHints => const [];
  @override
  List<String> get writeHints => const [];
  @override
  bool get passive => true;
  @override
  bool feed(List<int> chunk) => false;
  @override
  void reset() {}
}
