package com.modol.chrome_lite_flutter

import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "modol/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    try {
                        val stat = StatFs(
                            Environment.getExternalStorageDirectory().path
                        )
                        val total = stat.blockSizeLong * stat.blockCountLong
                        val free =
                            stat.blockSizeLong * stat.availableBlocksLong
                        val info = mapOf(
                            "usedBytes" to (total - free),
                            "totalBytes" to total
                        )
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "openFile" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val mime = contentResolver.getType(uri)
                            ?: guessMimeType(file.name)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = Intent.createChooser(
                            intent,
                            "Buka dengan"
                        )
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(chooser)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun guessMimeType(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "apk" -> "application/vnd.android.package-archive"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "7z" -> "application/x-7z-compressed"
            "rar" -> "application/vnd.rar"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mp3" -> "audio/mpeg"
            "txt" -> "text/plain"
            "html", "htm" -> "text/html"
            else -> "*/*"
        }
    }
}
