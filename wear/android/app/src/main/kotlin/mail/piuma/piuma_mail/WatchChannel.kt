package mail.piuma.piuma_mail

import android.app.Activity
import android.app.RemoteInput
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.wear.input.RemoteInputIntentHelper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * The watch's end of the link with the phone (`WatchLink.kt` in the phone
 * app, same paths). Dart calls `summary`, `refresh`, `open`, `act` and
 * `speak`; the phone's answers come back to Dart as `summary` and `text`.
 */
class WatchChannel(private val activity: Activity, messenger: BinaryMessenger) :
    DataClient.OnDataChangedListener, MessageClient.OnMessageReceivedListener {

    private val channel = MethodChannel(messenger, "mail.piuma.wear/link")
    private val main = Handler(Looper.getMainLooper())
    private var speaking: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "summary" -> background(result) { lastSummary() }
                "refresh" -> background(result) { send(REFRESH, ByteArray(0)); null }
                "open" -> background(result) {
                    send(OPEN, (call.arguments as String).toByteArray(Charsets.UTF_8)); null
                }
                "act" -> background(result) {
                    send(ACT, (call.arguments as String).toByteArray(Charsets.UTF_8)); null
                }
                "speak" -> speak(call.arguments as String, result)
                else -> result.notImplemented()
            }
        }
    }

    fun listen() {
        Wearable.getDataClient(activity).addListener(this)
        Wearable.getMessageClient(activity).addListener(this)
    }

    fun stop() {
        Wearable.getDataClient(activity).removeListener(this)
        Wearable.getMessageClient(activity).removeListener(this)
    }

    fun rotary(pixels: Float) {
        channel.invokeMethod("rotary", pixels.toDouble())
    }

    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED || event.dataItem.uri.path != INBOX) continue
            val json = DataMapItem.fromDataItem(event.dataItem).dataMap.getString("json") ?: continue
            main.post { channel.invokeMethod("summary", json) }
            // The app lock closed on the phone: no summary with mail stays
            // kept here (one from an earlier phone, or left behind).
            if (locked(json)) Thread { forgetMail(generation(json)) }.start()
        }
    }

    /** Removes the kept summaries with mail older than generation [upTo]. */
    private fun forgetMail(upTo: Long) {
        try {
            val client = Wearable.getDataClient(activity)
            val items = Tasks.await(client.getDataItems(inboxUri()), WAIT_SECONDS, TimeUnit.SECONDS)
            val stale = try {
                items.mapNotNull { item ->
                    val json = DataMapItem.fromDataItem(item).dataMap.getString("json")
                    item.uri.takeIf { json == null || (!locked(json) && generation(json) < upTo) }
                }
            } finally {
                items.release()
            }
            for (uri in stale) {
                Tasks.await(client.deleteDataItems(uri), WAIT_SECONDS, TimeUnit.SECONDS)
            }
        } catch (e: Exception) {
            // No Data Layer now: the phone's next summary replaces it.
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != TEXT) return
        val json = String(event.data, Charsets.UTF_8)
        main.post { channel.invokeMethod("text", json) }
    }

    private fun inboxUri(): Uri = Uri.Builder().scheme("wear").path(INBOX).build()

    /**
     * The summary the phone sent last, as the Data Layer keeps it: of
     * several (another phone's, say), the newest generation, and a locked
     * one over one with mail of the same generation.
     */
    private fun lastSummary(): String? {
        val items = Tasks.await(
            Wearable.getDataClient(activity).getDataItems(inboxUri()),
            WAIT_SECONDS,
            TimeUnit.SECONDS,
        )
        val kept = try {
            items.mapNotNull { DataMapItem.fromDataItem(it).dataMap.getString("json") }
        } finally {
            items.release()
        }
        return kept.maxWithOrNull(compareBy<String>({ generation(it) }, { locked(it) }))
    }

    private fun generation(json: String): Long = try {
        JSONObject(json).optLong("gen", 0L)
    } catch (e: Exception) {
        0L
    }

    private fun locked(json: String): Boolean = try {
        JSONObject(json).optBoolean("locked", false)
    } catch (e: Exception) {
        false
    }

    /** Sends to every phone connected now; there is one, the paired one. */
    private fun send(path: String, data: ByteArray) {
        val nodes = Tasks.await(Wearable.getNodeClient(activity).connectedNodes, WAIT_SECONDS, TimeUnit.SECONDS)
        val messages = Wearable.getMessageClient(activity)
        for (node in nodes) {
            Tasks.await(messages.sendMessage(node.id, path, data), WAIT_SECONDS, TimeUnit.SECONDS)
        }
    }

    /** Voice, keyboard or handwriting, as the watch offers them. */
    private fun speak(label: String, result: MethodChannel.Result) {
        speaking?.success(null)
        speaking = result
        val input = RemoteInput.Builder(REPLY).setLabel(label).build()
        val intent = RemoteInputIntentHelper.createActionRemoteInputIntent()
        RemoteInputIntentHelper.putRemoteInputsExtra(intent, listOf(input))
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, SPEAK)
    }

    /** The system input answered; false when it wasn't asked by us. */
    fun heard(requestCode: Int, data: Intent?): Boolean {
        if (requestCode != SPEAK) return false
        val text = data?.let { RemoteInput.getResultsFromIntent(it)?.getCharSequence(REPLY)?.toString() }
        speaking?.success(text)
        speaking = null
        return true
    }

    /** Runs [work] off the main thread, answering Dart on it. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            val answer = try {
                work()
            } catch (e: Exception) {
                // No phone, or the Data Layer is not there.
                null
            }
            main.post { result.success(answer) }
        }.start()
    }

    companion object {
        // The phone app's paths (WatchLink.kt).
        private const val INBOX = "/piuma/inbox"
        private const val REFRESH = "/piuma/refresh"
        private const val ACT = "/piuma/act"
        private const val OPEN = "/piuma/open"
        private const val TEXT = "/piuma/text"

        private const val REPLY = "reply"
        private const val SPEAK = 7
        private const val WAIT_SECONDS = 10L
    }
}
