package mail.piuma.piuma_mail

import android.content.Intent
import android.view.MotionEvent
import android.view.ViewConfiguration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Piuma Mail on the watch: Flutter draws, [WatchChannel] talks to the phone. */
class MainActivity : FlutterActivity() {
    private var link: WatchChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        link = WatchChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        link?.listen()
    }

    override fun onPause() {
        link?.stop()
        super.onPause()
    }

    /** The crown or the bezel turned: the list on screen scrolls (`RoundScroll`). */
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(android.view.InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            val factor = ViewConfiguration.get(this).scaledVerticalScrollFactor
            link?.rotary(-event.getAxisValue(MotionEvent.AXIS_SCROLL) * factor / resources.displayMetrics.density)
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    @Deprecated("The system input answers here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (link?.heard(requestCode, data) != true) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
