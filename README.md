# 数据视界 (DataVision)

只读**控制器**和**电池保护板**数据的蓝牙工具。不做仪表、不算车速、不写参数——打开就是一堆实时读数，
插上就能看。一套 Flutter 代码同时出 iOS / Android 两个包。

## 支持什么

| 类别 | 品牌 | 说明 |
|---|---|---|
| 控制器 | 凌博 LBMC | `AA 55 LEN CMD … SUM8`，服务 FFF0（写 FFF2 / 通知 FFF1），先读标定帧拿换算分母，所以全系电压平台通用 |
| 控制器 | 远驱 Fardriver / VOTOL / YuanQu | 固定 16 字节 `AA` 帧、CRC 初值 0x7F3C，**被动推送**不发请求；电压/电流/双温/SOC/挡位直读 |
| 控制器 | VESC 系（Flipsky / MakerX / Trampa / Spintend…） | Nordic UART + `COMM_GET_VALUES`，刷 VESC 固件的都通用 |
| 保护板 | 蚂蚁 ANT | `7E A1 … CRC16 AA 55`。**三条信道依次回退**：第一条不回数据就换第二条、第三条，跑通后记住 |
| 保护板 | 极空 JK | `55 AA EB 90` 300 字节帧，JK02 布局，单体/温度/均衡/MOS/告警全读 |

认不出来的设备照样能连：**数据台**会显示 GATT 清单和原始十六进制字节流，把字节发过来就能加一个驱动。

## 用起来是什么样

1. 第一次：点右上角蓝牙图标 → 搜索 → 选中设备。
2. 之后：**只要搜到就自动连**。设备 id 存在本地，App 启动、从后台回来、断线，都会自己扫回来重连。
3. 控制器和保护板是**两条独立链路**，一个掉线不影响另一个；扫描会话全局共用一份（两个链路各扫一次会互相打断）。

## 代码结构

```
lib/
  ble/scanner.dart     全局扫描总线（一条扫描会话，广播给两条链路）
  ble/link.dart        链路状态机：自动连 / 信道回退 / 掉线重连 / 首帧嗅探
  drivers/driver.dart  驱动接口（加品牌只写一个文件）
  drivers/lingbo.dart  凌博
  drivers/fardriver.dart 远驱
  drivers/vesc.dart    VESC
  drivers/ant_bms.dart 蚂蚁保护板
  drivers/jk_bms.dart  极空保护板
  ui/                  控制器页 / 保护板页 / 数据台 / 设置
tools/make_icon.py     图标生成（改设计只改这里）
tools/push_repo.py     代理环境下用 REST API 推仓库
```

加一个品牌 = 新建 `drivers/xxx.dart` 实现 `DeviceDriver`，在 `drivers/registry.dart` 里注册一行。
传输层和界面一行都不用改。

### 信道回退怎么做的

驱动给出一份**有序**的写入信道清单（`writeHints`），链路按顺序试：

```
第 1 条不回报文 → 1.6 秒后换第 2 条 → 再换第 3 条 → 循环
跑通任意一条 → 锁定，并写进本地；下次连上直接用这条
已在线但 6 秒没有新帧 → 先换信道两次，还不行才断开重连
```

## 构建

本地（Windows 也能出 APK）：

```bash
flutter pub get
flutter build apk --release           # build/app/outputs/flutter-apk/app-release.apk
```

iOS 包只能在 macOS 上出，推送到 GitHub 后由 Actions 自动完成：

```bash
# .github/workflows/build.yml：macos-15 上 flutter build ios --no-codesign → ad-hoc 签名 → IPA
# 同时 ubuntu 上出一个 APK
```

iOS 包为 ad-hoc 签名，越狱设备用 TrollStore / AppSync / Sideloadly 安装。

APK 用仓库内固定 keystore 签名（`android/app/datavision.jks`），后续版本可直接覆盖安装。

## 已知边界

- 九号 / 小牛 / 博世等原厂中控是**加密私有协议**，公开资料不足以实现，暂不支持（能连上看字节，读不出数）。
- 极空目前按 JK02_32S 布局解析；24S 老固件（JK02_24S）字段偏移不同，遇到再说。
- 只读，不提供任何写参数 / 刷固件功能。
