package mail.piuma.piuma_mail

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saved attachments (`phone_files.dart`): into the shared Downloads through
 * the media store, which needs no storage permission from Android 10, and
 * opened with the app the person picks.
 */
internal class Files(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "mail.piuma/files").setMethodCallHandler { call, result ->
            try {
                val path = call.argument<String>("path")!!
                when (call.method) {
                    "toDownloads" -> result.success(toDownloads(File(path)))
                    "open" -> {
                        open(path)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("files", e.message, null)
            }
        }
    }

    /** The file's new address, or null before Android 10 (it stays put). */
    private fun toDownloads(file: File): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            // The media store adds " (1)" when the name is taken.
            put(MediaStore.Downloads.DISPLAY_NAME, file.name)
            put(MediaStore.Downloads.MIME_TYPE, mimeOf(file.name))
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Downloads refused the file")
        try {
            resolver.openOutputStream(uri)!!.use { out ->
                file.inputStream().use { it.copyTo(out) }
            }
            resolver.update(uri, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        } finally {
            file.delete()
        }
        return uri.toString()
    }

    private fun open(path: String) {
        val uri = Uri.parse(path)
        if (uri.scheme != "content") {
            throw IllegalArgumentException("Only files in Downloads can be opened")
        }
        val type = activity.contentResolver.getType(uri) ?: "application/octet-stream"
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, type)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(view, null))
    }

    private fun mimeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }
}
