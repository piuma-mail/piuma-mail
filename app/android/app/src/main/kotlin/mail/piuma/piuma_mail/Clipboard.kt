package mail.piuma.piuma_mail

import android.content.ClipboardManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The picture on the system clipboard, for compose's "Paste picture"
 * (`clipboard_picture.dart`): its bytes, read through the content
 * resolver, or null when the clipboard holds no picture. Files bigger
 * than [MAX_BYTES] are left alone, so a huge one never fills memory.
 */
internal class Clipboard(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "mail.piuma/clipboard").setMethodCallHandler { call, result ->
            when (call.method) {
                "picture" -> try {
                    result.success(picture())
                } catch (e: Exception) {
                    result.error("clipboard", e.message, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun picture(): ByteArray? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return null
        val resolver = context.contentResolver
        for (i in 0 until clip.itemCount) {
            val uri = clip.getItemAt(i).uri ?: continue
            val type = resolver.getType(uri) ?: continue
            if (!type.startsWith("image/")) continue
            resolver.openAssetFileDescriptor(uri, "r")?.use { fd ->
                if (fd.length > MAX_BYTES) return null
            }
            resolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                return if (bytes.size > MAX_BYTES) null else bytes
            }
        }
        return null
    }

    companion object {
        /** The most compose takes for one message (`maxDraftFilesSize`). */
        const val MAX_BYTES = 18L * 1000 * 1000
    }
}
