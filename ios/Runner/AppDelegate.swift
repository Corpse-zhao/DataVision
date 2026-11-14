import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 应用级通道（不挂在某个插件上）：目前只有屏幕常亮
    // 通道名与 Android 侧 MainActivity.kt 的 datavision/native 保持一致
    let channel = FlutterMethodChannel(
      name: "datavision/native",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepAwake":
        let args = call.arguments as? [String: Any]
        let on = args?["on"] as? Bool ?? false
        // 只在主线程改这个属性，个别系统版本在别的线程改会不生效
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
