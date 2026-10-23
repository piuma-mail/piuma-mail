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
import java.util.concurrent.TimeUnit

/**
 * A paired watch (`WatchWearOS`): the phone keeps the mail and sends the
 * watch a small summary of the inbox (`watch.rs`), and does what the
 * watch's buttons ask. No account or password goes to the watch.
 *
 * The paths, shared with `wear/android/.../WatchChannel.kt`:
 * - [INBOX], a data item: the summary, as JSON.
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

    /** Sends the summary when a watch is there, on a thread of its own. */
    fun publish(context: Context) {
        val app = context.applicationContext
        Thread { publishNow(app) }.start()
    }

    /** Sends the summary when a watch is there; waits, so never on the main thread. */
    fun publishNow(context: Context) {
        if (!watchNear(context)) return
        val json = try {
            Background.openEngine(context)
            MailNative.watchSummary()
        } catch (e: Throwable) {
            ""
        }
        if (json.isEmpty()) return
        val request = PutDataMapRequest.create(INBOX).apply {
            dataMap.putString("json", json)
        }.asPutDataRequest().setUrgent()
        try {
            Tasks.await(Wearable.getDataClient(context).putDataItem(request), WAIT_SECONDS, TimeUnit.SECONDS)
        } catch (e: Exception) {
            // The watch went away: it asks again when it opens.
        }
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
                val text = try {
                    Background.openEngine(context)
                    MailNative.watchText(payload, offset)
                } catch (e: Throwable) {
                    ""
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
