package mail.piuma.piuma_mail

import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * The picture on the system clipboard, for compose's "Paste picture"
 * (`clipboard_picture.dart`): its bytes, read through the content
 * resolver, or null when the clipboard holds no picture. Read off the
 * main thread; a picture bigger than [MAX_BYTES] is left alone, read up
 * to that much at most even when its size is unknown, so a huge one never
 * fills memory.
 */
internal class Clipboard(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "mail.piuma/clipboard").setMethodCallHandler { call, result ->
            when (call.method) {
                // The clipboard is read on the main thread, the picture
                // itself on another, and the answer goes back on the main.
                "picture" -> {
                    val clip = clipItems()
                    reader.execute {
                        val answer = runCatching { picture(clip) }
                        main.post {
                            answer.fold(
                                { result.success(it) },
                                { result.error("clipboard", it.message, null) },
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private val reader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private fun clipItems(): List<android.net.Uri> {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return emptyList()
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    }

    private fun picture(uris: List<android.net.Uri>): ByteArray? {
        val resolver = context.contentResolver
        for (uri in uris) {
            val type = resolver.getType(uri) ?: continue
            if (!type.startsWith("image/")) continue
            resolver.openAssetFileDescriptor(uri, "r")?.use { fd ->
                if (fd.length > MAX_BYTES) return null
            }
            resolver.openInputStream(uri)?.use { input ->
                // The size may be unknown (-1): never read past the limit.
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) return null
                    out.write(buffer, 0, n)
                }
                return out.toByteArray()
            }
        }
        return null
    }

    companion object {
        /** The most compose takes for one message (`maxDraftFilesSize`). */
        const val MAX_BYTES = 18L * 1000 * 1000
    }
}
