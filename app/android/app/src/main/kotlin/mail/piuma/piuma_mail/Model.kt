package mail.piuma.piuma_mail

import android.util.Log
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Gemini Nano, the model Android keeps on the device through AICore, for
 * "In short" (`on_device_model.dart`). Phones without it say
 * "unavailable" and the app keeps its own rules.
 */
internal class Model(messenger: BinaryMessenger) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var client: GenerativeModel? = null
    private var downloading = false

    init {
        MethodChannel(messenger, "mail.piuma/model").setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    when (call.method) {
                        "status" -> result.success(status().also { Log.i(TAG, "Gemini Nano: $it") })
                        "generate" -> {
                            val started = System.currentTimeMillis()
                            val answer = generate(call.argument<String>("prompt")!!)
                            // Only that it ran and how long it took: never the mail.
                            Log.i(TAG, "In short written by Gemini Nano in ${System.currentTimeMillis() - started} ms")
                            result.success(answer)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Gemini Nano failed: ${e.javaClass.simpleName}")
                    result.error("model", e.message, null)
                }
            }
        }
    }

    private companion object {
        const val TAG = "PiumaModel"
    }

    private fun model(): GenerativeModel = client ?: Generation.getClient().also { client = it }

    private suspend fun status(): String {
        return when (model().checkStatus()) {
            FeatureStatus.AVAILABLE -> "available"
            FeatureStatus.DOWNLOADING -> "downloading"
            FeatureStatus.DOWNLOADABLE -> {
                // AICore fetches it once for every app on the phone; until
                // then the rules' words stay.
                if (!downloading) {
                    downloading = true
                    scope.launch {
                        try {
                            model().download().collect {}
                        } catch (e: Exception) {
                            // Tried again the next time the app starts.
                        }
                    }
                }
                "downloading"
            }
            else -> "unavailable"
        }
    }

    private suspend fun generate(prompt: String): String? {
        val response = model().generateContent(
            generateContentRequest(TextPart(prompt)) {
                temperature = 0.2f
                maxOutputTokens = 160
            },
        )
        return response.candidates.firstOrNull()?.text
    }
}
