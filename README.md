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

1. 第一次：点右上角蓝牙图标 → 搜索 → 选中设备。列表默认只显示认识的设备（按品牌名 / 服务 UUID 认），耳机、手环、共享单车锁这些收在「显示全部」后面。
2. 之后：**只要搜到就自动连**。设备 id 存在本地，App 启动、从后台回来、断线，都会自己扫回来重连。
3. 控制器和保护板是**两条独立链路**，一个掉线不影响另一个；扫描会话全局共用一份（两个链路各扫一次会互相打断）。
4. 数据页一屏看全：**竖屏上控制器、下保护板；横屏左控制器、右保护板**。横屏时底部导航收进顶栏，多出约 60dp 给数据。
5. 每个数据板块都是同一个节奏：小格子（19px 数字，一行四格）→ 细横线小标题 → 图/柱/进度条。富余高度交给功率走势和单体柱形图，不摊成留白。
6. 点任意一张卡 → 弹出该设备的**全部指标 + 协议状态**（主指标、明细都在里面）。
7. 设置里有「不息屏」开关（默认关）：打开后看数据时屏幕不自己黑掉；只在本 App 前台生效，Android 走 `FLAG_KEEP_SCREEN_ON`，iOS 走 `isIdleTimerDisabled`，退出即恢复。

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
  core/updater.dart    在线更新：查 GitHub release / 比版本 / 下 APK（带镜像回退）
  core/native.dart     原生通道封装（只有 Android 实现了装 APK）
  ui/                  数据页（横竖屏自适应）/ 数据台 / 设置 / 更新弹窗
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

## 在线更新

更新源不是自建服务器，是仓库自己的 GitHub Releases —— 仓库公开，接口和资产都免费。

查版本有两条线路，一条不通自动走另一条：

1. `GET /repos/Corpse-zhao/DataVision/releases?per_page=10` —— 拿列表，自己挑版本号最大的那条。
   **不用 `/releases/latest`**：它不返回被标成 prerelease 的版本，而 CI 早期确实把 release 标成了
   预发布，接口直接 404，客户端看起来就跟"网络不通"一模一样 —— 这个坑真踩过。
2. `version.json`（仓库根目录）经 jsDelivr / raw / ghfast 多线路并发拉取，哪条先回来用哪条。

`version.json` 里的版本号必须和 `pubspec.yaml` 一致，`test/updater_test.dart` 里有条测试专门守着这件事，
不一致直接构建失败 —— 否则更新通道会指向一个不存在的包。

两端能力不一样，这是系统决定的，不是实现取舍：

| | Android | iOS |
|---|---|---|
| 检查更新 | 启动 / 回前台自动查（6 小时节流） | 同左 |
| 下载 | App 内直接下 APK，带进度条 | 跳到 Safari 下 IPA |
| 安装 | 交给系统安装器覆盖安装 | 必须用全能签重签后手动装 |

Android 侧要点：

- `REQUEST_INSTALL_PACKAGES` 权限 + `FileProvider`（authority `com.corpsezhao.datavision.fileprovider`），
  APK 落在 `getExternalFilesDir()/update/`，`file_paths.xml` 里只开这一个目录和 cache。
- 用户还没允许「安装未知应用」时，`installApk` 返回 `need_permission` 并直接把设置页拉起来，
  授权后回来再点一次即可，包不会重下。
- 覆盖安装的前提是新包用**同一个 keystore** 签（`android/app/datavision.jks`）。签名变了系统会拒绝覆盖，
  只能卸载重装，本地记住的设备和信道会丢。
- 国内直连 `objects.githubusercontent.com` 常断，下载按「原始地址 → ghfast.top → ghproxy.net」顺序试，
  前一个失败自动换下一个。

iOS 侧为什么不能自动更新：IPA 的签名绑死了 bundle id、证书和设备列表，装新版本必须重新签名，
系统也没有给 App 提供「安装另一个 App」的接口。自签证书还没有 APNs 权限，所以连推送提醒都发不出去，
只能靠 App 打开时自己查。想真·一键更新得走 App Store 或 TestFlight（$99/年）。

## 已知边界

- 九号 / 小牛 / 博世等原厂中控是**加密私有协议**，公开资料不足以实现，暂不支持（能连上看字节，读不出数）。
- 极空目前按 JK02_32S 布局解析；24S 老固件（JK02_24S）字段偏移不同，遇到再说。
- 只读，不提供任何写参数 / 刷固件功能。
