package com.modol.chrome_lite_flutter

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val channelName = "com.modol.chrome_lite_flutter/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToDownloads") {
                    val path = call.argument<String>("path")
                    val fileName = call.argument<String>("fileName")
                    if (path == null || fileName == null) {
                        result.error("BAD_ARGS", "path/fileName kosong", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(moveToDownloads(File(path), fileName))
                    } catch (e: Exception) {
                        result.error("MOVE_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Pindahkan [file] ke folder Unduhan publik supaya bisa ditemukan
    /// pengguna di aplikasi File. Kembalikan path tampilan tujuan, atau
    /// null bila gagal (berkas sumber tetap utuh).
    private fun moveToDownloads(file: File, fileName: String): String? {
        if (!file.exists()) return null
        val downloadsDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val uniqueName = uniqueNameIn(downloadsDir, fileName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeFromName(uniqueName))
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: return null
            try {
                val out = contentResolver.openOutputStream(uri) ?: run {
                    contentResolver.delete(uri, null, null)
                    return null
                }
                out.use { stream ->
                    FileInputStream(file).use { input -> input.copyTo(stream) }
                }
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                return null
            }
            file.delete()
            return "${downloadsDir.absolutePath}/$uniqueName"
        } else {
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val dest = File(downloadsDir, uniqueName)
            if (!file.renameTo(dest)) {
                try {
                    FileInputStream(file).use { input ->
                        dest.outputStream().use { out -> input.copyTo(out) }
                    }
                } catch (e: Exception) {
                    return null
                }
                file.delete()
            }
            return dest.absolutePath
        }
    }

    /// Cari nama yang belum dipakai di [dir] (tambah " (n)" bila perlu).
    private fun uniqueNameIn(dir: File, name: String): String {
        var candidate = name
        var n = 1
        while (File(dir, candidate).exists()) {
            val dot = name.lastIndexOf('.')
            val base = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""
            candidate = "$base ($n)$ext"
            n++
        }
        return candidate
    }

    private fun mimeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "apk" -> "application/vnd.android.package-archive"
            "txt" -> "text/plain"
            "html", "htm" -> "text/html"
            else -> "application/octet-stream"
        }
    }
}
