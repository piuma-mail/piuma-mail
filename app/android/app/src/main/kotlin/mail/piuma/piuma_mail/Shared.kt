package mail.piuma.piuma_mail

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * What other apps hand Piuma (lib/outside/ in Dart, over "piuma/shell"):
 * `mailto:` links (SENDTO, VIEW), shares (SEND, SEND_MULTIPLE: text,
 * links, files, pictures) and email files (VIEW of message/rfc822).
 *
 * Everything in an intent is untrusted. Only `content:` files of other
 * apps are read (never `file:`, never one of Piuma's own providers),
 * copied into the app's cache under a name of ours with size caps; the
 * name the other app gives is only passed along as text, and Dart cleans
 * it. Text has length caps. Nothing else in the intent is used.
 */
internal class Shared(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "piuma/shell")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var ready = false
    private val waiting = mutableListOf<Map<String, Any?>>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready = true
                    val all = waiting.toList()
                    waiting.clear()
                    all.forEach(::send)
                    result.success(null)
                }
                "defaultMail" -> result.success(defaultMail())
                "makeDefault" -> result.success(makeDefault())
                else -> result.notImplemented()
            }
        }
    }

    fun stop() {
        worker.shutdown()
    }

    private fun send(data: Map<String, Any?>) {
        if (!ready) {
            if (waiting.size < 16) waiting.add(data)
            return
        }
        channel.invokeMethod("shared", data)
    }

    /** Reads [intent], if it is one of ours, and hands it to Dart. */
    fun handle(intent: Intent?) {
        val read = try {
            read(intent ?: return)
        } catch (e: Exception) {
            // A malformed intent (a bad parcel, wrong extra types) is
            // simply not acted on.
            null
        } ?: return
        read()
    }

    /** What to do with [intent], or null when it isn't for us. */
    private fun read(intent: Intent): (() -> Unit)? {
        // Opened again from Recents: the intent was handled back then.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val action = intent.action ?: return null
        val data = intent.data
        return when {
            (action == Intent.ACTION_SENDTO || action == Intent.ACTION_VIEW) &&
                data?.scheme.equals("mailto", ignoreCase = true) -> {
                val message = mapOf(
                    "link" to cap(data.toString(), LINK_MAX),
                    "subject" to text(intent, Intent.EXTRA_SUBJECT, SUBJECT_MAX),
                    "text" to text(intent, Intent.EXTRA_TEXT, TEXT_MAX),
                    "to" to addresses(intent, Intent.EXTRA_EMAIL),
                    "cc" to addresses(intent, Intent.EXTRA_CC),
                    "bcc" to addresses(intent, Intent.EXTRA_BCC),
                )
                val run: () -> Unit = { send(message) }
                run
            }
            action == Intent.ACTION_VIEW && data != null && isEmail(intent, data) -> {
                if (!readable(data)) return null
                val run: () -> Unit = {
                    worker.execute {
                        val path = copy(data, EML_MAX)?.path
                        if (path != null) main.post { send(mapOf("eml" to path)) }
                    }
                }
                run
            }
            action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE -> {
                val streams = streams(intent).filter(::readable).take(FILES_MAX + 1)
                val subject = text(intent, Intent.EXTRA_SUBJECT, SUBJECT_MAX)
                val body = text(intent, Intent.EXTRA_TEXT, TEXT_MAX)
                val to = addresses(intent, Intent.EXTRA_EMAIL)
                val cc = addresses(intent, Intent.EXTRA_CC)
                val bcc = addresses(intent, Intent.EXTRA_BCC)
                val run: () -> Unit = {
                    worker.execute {
                        cleanOld()
                        val files = mutableListOf<Map<String, String>>()
                        var skipped = 0
                        var total = 0L
                        for (uri in streams) {
                            val copied = if (files.size < FILES_MAX) copy(uri, FILE_MAX) else null
                            if (copied == null || total + copied.length() > TOTAL_MAX) {
                                copied?.delete()
                                skipped++
                                continue
                            }
                            total += copied.length()
                            files.add(mapOf("path" to copied.path, "name" to displayName(uri)))
                        }
                        val message = mapOf(
                            "subject" to subject,
                            "text" to body,
                            "to" to to,
                            "cc" to cc,
                            "bcc" to bcc,
                            "files" to files,
                            "skipped" to skipped,
                        )
                        main.post { send(message) }
                    }
                }
                run
            }
            else -> null
        }
    }

    private fun isEmail(intent: Intent, data: Uri): Boolean {
        val type = intent.type ?: try {
            activity.contentResolver.getType(data)
        } catch (e: Exception) {
            null
        }
        if (type.equals("message/rfc822", ignoreCase = true)) return true
        return data.lastPathSegment?.lowercase()?.endsWith(".eml") == true
    }

    /**
     * A file Piuma may read: another app's `content:` file. Never a
     * `file:` path (it could name Piuma's own data) and never one of
     * Piuma's own providers, under any name or user.
     */
    private fun readable(uri: Uri): Boolean {
        if (!uri.scheme.equals("content", ignoreCase = true)) return false
        val authority = uri.authority ?: return false
        // The provider Android would ask, whatever the authority claims:
        // a user before an `@` (`0@...`, another profile) is not part of
        // its name. Refused when no provider answers to it.
        val name = authority.substringAfterLast('@')
        val provider = try {
            activity.packageManager.resolveContentProvider(name, 0)
        } catch (e: Exception) {
            null
        } ?: return false
        return provider.packageName != activity.packageName
    }

    private fun streams(intent: Intent): List<Uri> {
        val out = LinkedHashSet<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            list?.filterNotNull()?.let(out::addAll)
        } else {
            val one = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            one?.let(out::add)
        }
        // Some apps only put them in the clip, with the read grant.
        intent.clipData?.let { clip ->
            for (i in 0 until minOf(clip.itemCount, FILES_MAX + 1)) {
                clip.getItemAt(i).uri?.let(out::add)
            }
        }
        return out.toList()
    }

    /** Copies [uri] into the cache under a name of ours; null past [max]. */
    private fun copy(uri: Uri, max: Long): File? {
        val dir = File(activity.cacheDir, "shared").apply { mkdirs() }
        val file = File(dir, UUID.randomUUID().toString())
        try {
            val input = activity.contentResolver.openInputStream(uri) ?: return null
            input.use { from ->
                file.outputStream().use { to ->
                    val buffer = ByteArray(64 * 1024)
                    var written = 0L
                    while (true) {
                        val n = from.read(buffer)
                        if (n < 0) break
                        written += n
                        if (written > max) {
                            to.close()
                            file.delete()
                            return null
                        }
                        to.write(buffer, 0, n)
                    }
                }
            }
            return file
        } catch (e: Exception) {
            file.delete()
            return null
        }
    }

    /** The name the other app gives the file: text only, cleaned in Dart. */
    private fun displayName(uri: Uri): String = try {
        activity.contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) cap(c.getString(0), NAME_MAX) else null
        } ?: ""
    } catch (e: Exception) {
        ""
    }

    /** Copies older than a day: a share that was never sent. */
    private fun cleanOld() {
        val dir = File(activity.cacheDir, "shared")
        val day = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        dir.listFiles()?.forEach { if (it.isFile && it.lastModified() < day) it.delete() }
    }

    private fun text(intent: Intent, key: String, max: Int): String = try {
        cap(intent.getCharSequenceExtra(key)?.toString() ?: "", max)
    } catch (e: Exception) {
        ""
    }

    private fun addresses(intent: Intent, key: String): List<String> {
        val list = try {
            intent.getStringArrayExtra(key)?.toList()
                ?: intent.getStringExtra(key)?.let(::listOf)
                ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        return list.filterNotNull().take(ADDRESSES_MAX).map { cap(it, ADDRESS_MAX) }
    }

    /** Who opens `mailto:` links: "piuma", "other" or "none". */
    private fun defaultMail(): String {
        val who = holder() ?: return "none"
        return if (who == activity.packageName) "piuma" else "other"
    }

    /** The app that opens `mailto:` links without asking, if one does. */
    private fun holder(): String? {
        val probe = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val info = activity.packageManager.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            ?: return null
        val activityInfo = info.activityInfo ?: return null
        // The chooser: nothing is set, Android asks.
        if (activityInfo.packageName == "android" || activityInfo.name.contains("Resolver")) {
            return null
        }
        return activityInfo.packageName
    }

    /**
     * Android has no "default mail app" setting: another app holds
     * `mailto:` until its defaults are cleared, then Android asks and the
     * person picks Piuma, Always. With one set, its App info opens there.
     */
    private fun makeDefault(): String {
        val state = defaultMail()
        if (state == "other") {
            try {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", holder(), null)),
                )
            } catch (e: ActivityNotFoundException) {
                // No App info screen on this phone.
            }
        }
        return state
    }

    private fun cap(text: String, max: Int) = if (text.length <= max) text else text.substring(0, max)

    companion object {
        const val LINK_MAX = 256 * 1024
        const val SUBJECT_MAX = 4000
        const val TEXT_MAX = 100_000
        const val ADDRESSES_MAX = 100
        const val ADDRESS_MAX = 320
        const val NAME_MAX = 255
        const val FILES_MAX = 20

        /** One file shared, and all of them: what a message can carry. */
        const val FILE_MAX = 18_000_000L
        const val TOTAL_MAX = 18_000_000L

        /** An email file opened, as the engine reads at most. */
        const val EML_MAX = 50L * 1024 * 1024
    }
}
