package mail.piuma.piuma_mail

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * The app lock as the app left it (`app/lib/lock/`): `app-lock.json` next
 * to the database, there only while the lock is on. Not secret: the PIN's
 * hash is in the Keystore with the passwords. The background service and
 * the watch link read it so that, while the lock is on, notices say only
 * "New message" and the watch gets no mail.
 */
object AppLockFile {
    private fun file(context: Context) = File(context.filesDir, "app-lock.json")

    fun on(context: Context): Boolean = file(context).exists()

    /** What a notice says while the lock is on, in the app's language. */
    fun notice(context: Context): String {
        val text = try {
            JSONObject(file(context).readText()).optString("notice")
        } catch (e: Exception) {
            ""
        }
        return text.ifEmpty { "New message" }
    }
}
