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
 * app, same paths). Dart calls `summary`, `phones`, `refresh`, `open`,
 * `act` and `speak`; the phone's answers come back to Dart as `summary`
 * and `text`. A summary always goes to Dart with the phone (node) it came
 * from, `{"node", "json"}`: Dart shows mail only from the phone connected
 * now (`link.dart`).
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
                "phones" -> background(result) { connected().toList() }
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
            val node = event.dataItem.uri.host
            // Dart checks the phone and orders them (`link.dart`). Nothing
            // is deleted here: the phone puts every summary at the one
            // path, each replacing the last.
            main.post { channel.invokeMethod("summary", mapOf("node" to node, "json" to json)) }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != TEXT) return
        val json = String(event.data, Charsets.UTF_8)
        main.post { channel.invokeMethod("text", json) }
    }

    private fun inboxUri(): Uri = Uri.Builder().scheme("wear").path(INBOX).build()

    /**
     * The summary the phone sent last, as the Data Layer keeps it: one
     * item per phone that ever sent one ([KeptSummaries.pick]).
     */
    private fun lastSummary(): Map<String, String?>? {
        val connected = connected()
        val items = Tasks.await(
            Wearable.getDataClient(activity).getDataItems(inboxUri()),
            WAIT_SECONDS,
            TimeUnit.SECONDS,
        )
        val kept = try {
            items.mapNotNull { item ->
                val json = DataMapItem.fromDataItem(item).dataMap.getString("json") ?: return@mapNotNull null
                val m = try {
                    JSONObject(json)
                } catch (e: Exception) {
                    return@mapNotNull null
                }
                KeptSummary(item.uri.host, json, m.optLong("at", 0L), m.optBoolean("locked", false))
            }
        } finally {
            items.release()
        }
        val picked = KeptSummaries.pick(kept, connected) ?: return null
        return mapOf("node" to picked.node, "json" to picked.json)
    }

    /** The phones connected now; none when the Data Layer can't say. */
    private fun connected(): Set<String> = try {
        Tasks.await(Wearable.getNodeClient(activity).connectedNodes, WAIT_SECONDS, TimeUnit.SECONDS)
            .map { it.id }
            .toSet()
    } catch (e: Exception) {
        emptySet()
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
