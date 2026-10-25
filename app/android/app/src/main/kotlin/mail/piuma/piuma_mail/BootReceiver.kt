package mail.piuma.piuma_mail

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** After a reboot or an update, new mail keeps arriving as before. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                Background.apply(context.applicationContext)
        }
    }
}
