package mail.piuma.piuma_mail

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * A paired watch (`WatchWearOS`): the phone keeps the mail and sends the
 * watch a small summary of the inbox (`watch.rs`), and does what the
 * watch's buttons ask. No account or password goes to the watch.
 *
 * The paths, shared with `wear/android/.../WatchChannel.kt`:
 * - [INBOX], a data item: the summary, as JSON. Always this one path, so
 *   each summary replaces the last: the Data Layer keeps no older one
 *   from this phone for the watch to clean up.
 * - [REFRESH], from the watch: send the summary again.
 * - [ACT], from the watch: `{"payload","action","until","text"}`, as a notice's button.
 * - [OPEN], from the watch: an email's payload; the words go back on [TEXT].
 *
 * A phone with no Piuma watch near it does nothing.
 */
object WatchLink {
    const val INBOX = "/piuma/inbox"
    const val REFRESH = "/piuma/refresh"
    const val ACT = "/piuma/act"
    const val OPEN = "/piuma/open"
    const val TEXT = "/piuma/text"

    // Declared by the watch app, in its res/values/wear.xml.
    private const val CAPABILITY = "piuma_watch"
    private const val WAIT_SECONDS = 10L

    /** The summary while the app lock is on (`wear/lib/summary.dart`). */
    private fun locked(at: Long) = """{"at":$at,"locked":true,"accounts":[],"rows":[],"templates":[]}"""

    /** Sends the summary when a watch is there, on a thread of its own. */
    fun publish(context: Context) {
        val app = context.applicationContext
        Thread { publishNow(app) }.start()
    }

    /** One summary on its way at a time ([publishNow]). */
    private val publishing = Any()

    /**
     * Sends the summary when a watch is there; waits, so never on the main
     * thread. One at a time, each with a higher generation ("gen") than
     * the last, which the watch uses to drop one that arrives late: a
     * summary with mail made just before the lock closed can't land after
     * the locked one. Each also carries this install's [epoch]: the count
     * starts again on another phone or after a reinstall, and the watch
     * takes a summary from another epoch whatever its generation.
     */
    fun publishNow(context: Context) {
        if (!watchNear(context)) return
        synchronized(publishing) {
            val mail = if (AppLockFile.on(context)) {
                ""
            } else {
                try {
                    Background.openEngine(context)
                    MailNative.watchSummary()
                } catch (e: Throwable) {
                    ""
                }
            }
            // Checked again once the summary is made, just before it goes:
            // the lock is on, so the watch is told so and gets no mail.
            val json = if (AppLockFile.on(context)) {
                locked(System.currentTimeMillis() / 1000)
            } else {
                mail
            }
            if (json.isEmpty()) return
            val stamped = try {
                val (epoch, gen) = nextGeneration(context)
                stamp(json, epoch, gen)
            } catch (e: IllegalArgumentException) {
                // Not a summary the watch would read.
                return
            }
            val request = PutDataMapRequest.create(INBOX).apply {
                dataMap.putString("json", stamped)
            }.asPutDataRequest().setUrgent()
            try {
                Tasks.await(Wearable.getDataClient(context).putDataItem(request), WAIT_SECONDS, TimeUnit.SECONDS)
            } catch (e: Exception) {
                // The watch went away: it asks again when it opens.
            }
        }
    }

    /** The last generation handed out, also kept across restarts. */
    private var lastGeneration = 0L

    /**
     * This install's epoch, made once at random and kept with the
     * generation: cleared app data or a reinstall start a new one, with
     * the count from zero again. Then the next generation.
     */
    private fun nextGeneration(context: Context): Pair<String, Long> {
        val prefs = context.getSharedPreferences("watch", Context.MODE_PRIVATE)
        val kept = prefs.getString("epoch", null)
        val epoch = kept ?: UUID.randomUUID().toString()
        val gen = nextGeneration(
            if (kept == null) 0L else maxOf(lastGeneration, prefs.getLong("gen", 0L)),
            System.currentTimeMillis(),
        )
        lastGeneration = gen
        prefs.edit().putString("epoch", epoch).putLong("gen", gen).commit()
        return epoch to gen
    }

    /**
     * After [last], never below the time of day in milliseconds: should
     * the kept one be lost (the app's data cleared), the count starts again
     * above what the watch saw before, as long as the clock wasn't set back.
     */
    internal fun nextGeneration(last: Long, nowMs: Long): Long = maxOf(last + 1, nowMs)

    /** [json], a summary object from the engine, with its epoch and generation first. */
    internal fun stamp(json: String, epoch: String, gen: Long): String {
        val body = json.trim()
        require(body.startsWith("{") && body.endsWith("}"))
        // A UUID: nothing in it to escape.
        require(epoch.isNotEmpty() && epoch.all { it in '0'..'9' || it in 'a'..'z' || it in 'A'..'Z' || it == '-' })
        val rest = body.substring(1).trimStart()
        val head = "\"epoch\":\"$epoch\",\"gen\":$gen"
        return if (rest == "}") "{$head}" else "{$head,$rest"
    }

    /** A watch with Piuma on it can be reached now. */
    private fun watchNear(context: Context): Boolean = try {
        Tasks.await(
            Wearable.getCapabilityClient(context)
                .getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE),
            WAIT_SECONDS,
            TimeUnit.SECONDS,
        ).nodes.isNotEmpty()
    } catch (e: Exception) {
        // No Google Play services, or no watch paired.
        false
    }
}

/** What the watch asks for; Android calls it on a thread of its own. */
class WatchListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val context = applicationContext
        when (event.path) {
            WatchLink.REFRESH -> WatchLink.publishNow(context)
            WatchLink.ACT -> {
                // Nothing is done from the watch while the app is locked.
                if (AppLockFile.on(context)) {
                    WatchLink.publishNow(context)
                    return
                }
                val ask = try {
                    JSONObject(String(event.data, Charsets.UTF_8))
                } catch (e: Exception) {
                    return
                }
                try {
                    Background.openEngine(context)
                    MailNative.act(
                        ask.getString("payload"),
                        ask.getString("action"),
                        ask.optLong("until", NoticeActions.tomorrowAtEight()),
                        ask.optString("text"),
                    )
                } catch (e: Throwable) {
                    // The watch shows the summary as it comes back.
                }
                WatchLink.publishNow(context)
            }
            WatchLink.OPEN -> {
                val payload = String(event.data, Charsets.UTF_8)
                val offset = TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60_000
                val text = if (AppLockFile.on(context)) {
                    ""
                } else {
                    try {
                        Background.openEngine(context)
                        MailNative.watchText(payload, offset)
                    } catch (e: Throwable) {
                        ""
                    }
                }
                val answer = text.ifEmpty { JSONObject().put("payload", payload).put("text", "").toString() }
                try {
                    Tasks.await(
                        Wearable.getMessageClient(context)
                            .sendMessage(event.sourceNodeId, WatchLink.TEXT, answer.toByteArray(Charsets.UTF_8)),
                        10,
                        TimeUnit.SECONDS,
                    )
                } catch (e: Exception) {
                    // The watch went away.
                }
            }
        }
    }
}
