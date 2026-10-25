package mail.piuma.piuma_mail

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

/**
 * "Shake to report" (`shake.dart`): an event on "mail.piuma/shake" each
 * time the phone is shaken. The accelerometer is only listened to while
 * Dart listens, which it does only with the setting on and the app in
 * front. "mail.piuma/sensors" says whether the phone has one at all.
 */
internal class Shake(context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler, SensorEventListener {
    private val sensors = context.getSystemService(SensorManager::class.java)
    private val accelerometer = sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sink: EventChannel.EventSink? = null

    /** Whether the last reading was above the threshold. */
    private var above = false
    /** When the first peak of a possible shake came, ms; 0 for none. */
    private var firstPeak = 0L
    /** When the last shake was told, ms. */
    private var lastShake = 0L

    init {
        EventChannel(messenger, "mail.piuma/shake").setStreamHandler(this)
        MethodChannel(messenger, "mail.piuma/sensors").setMethodCallHandler { call, result ->
            when (call.method) {
                "accelerometer" -> result.success(accelerometer != null)
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        above = false
        firstPeak = 0L
        accelerometer?.let { sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    /** Stops listening to the sensor, as when the activity goes. */
    fun stop() {
        sensors?.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val (x, y, z) = event.values
        val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
        val now = event.timestamp / 1_000_000
        val peak = g > THRESHOLD && !above
        above = g > THRESHOLD
        if (!peak || now - lastShake < DEBOUNCE_MS) return
        // Two peaks close together: a shake, not a bump or a drop.
        if (firstPeak != 0L && now - firstPeak <= WINDOW_MS) {
            firstPeak = 0L
            lastShake = now
            sink?.success(null)
        } else {
            firstPeak = now
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private companion object {
        /** In g: well above walking or a phone put down on a table. */
        const val THRESHOLD = 2.7f
        /** Two peaks within this make a shake. */
        const val WINDOW_MS = 500L
        /** No second shake this soon after one. */
        const val DEBOUNCE_MS = 1500L
    }
}
