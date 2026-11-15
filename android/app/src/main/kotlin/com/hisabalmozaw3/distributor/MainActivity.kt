package com.hisabalmozaw3.distributor

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
 * قناة app.update — التحديث من داخل التطبيق (UpdateService في Dart):
 *   info                -> { versionCode, versionName, abi, nativeLibDir, sdkInt }
 *   canInstall          -> هل يُسمح بتثبيت حزم من مصادر غير معروفة (أندرويد 8+)
 *   openInstallSettings -> يفتح شاشة "تثبيت تطبيقات غير معروفة" لهذا التطبيق
 *   install(path)       -> يفتح مثبّت النظام على APK داخل cache/updates (FileProvider)
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val pi = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode
                                   else @Suppress("DEPRECATION") pi.versionCode.toLong()
                        result.success(mapOf(
                            "versionCode" to code,
                            "versionName" to (pi.versionName ?: ""),
                            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                            // مجلد مكتبات الـ APK المثبّت (…/lib/arm64 أو …/lib/arm) — يحدد أي APK نُنزّل
                            "nativeLibDir" to (applicationInfo.nativeLibraryDir ?: ""),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ))
                    }
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(true)
                    }
                    "install" -> {
                        val f = File(call.argument<String>("path") ?: throw IllegalArgumentException("path"))
                        if (!f.exists()) throw IllegalStateException("file not found")
                        val uri = FileProvider.getUriForFile(this, "$packageName.update.fileprovider", f)
                        startActivity(Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }
    }

    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) packageManager.canRequestPackageInstalls() else true
}
