package com.corpsezhao.datavision

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 原生层只干两件事：把下载好的 APK 交给系统安装器、开外部链接。
 *
 * 下载放 Dart 里做（能拿进度），安装必须过原生：Android 8.0 之后要用 FileProvider
 * 给系统一个 content:// URI，而且用户得先允许「安装未知应用」——没允许时这里直接把设置页拉起来。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "datavision/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateDir" -> {
                        val dir = File(getExternalFilesDir(null), "update")
                        if (!dir.exists()) dir.mkdirs()
                        result.success(dir.absolutePath)
                    }

                    "canInstall" -> result.success(canInstallPackages())

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }

                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.error("bad_args", "url is required", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("no_browser", e.message, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Android 8.0+ 才有"安装未知应用"这个开关，更老的系统默认允许。 */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return "missing_file"

        if (!canInstallPackages()) {
            try {
                // 拉用户去开权限，回 App 再点一次即可
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (_: Exception) {
                // 个别 ROM 没这个页面
            }
            return "need_permission"
        }

        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "ok"
        } catch (e: Exception) {
            "error:${e.message}"
        }
    }
}
