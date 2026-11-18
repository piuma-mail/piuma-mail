package mail.piuma.piuma_mail

import android.content.Context
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Seals what a notice opens. MainActivity has to be exported (it is the
 * launcher), so any app can start it with any extras: a payload counts only
 * when it carries the HMAC of a key this installation made and keeps in its
 * private preferences, which no other app can read.
 */
internal object NoticeSeal {
    private const val PREFS = "notice_seal"
    private const val KEY = "key"
    private const val MARK = "\n#seal:"

    @Volatile
    private var cached: ByteArray? = null

    private fun key(context: Context): ByteArray {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val stored = prefs.getString(KEY, null)
            val key = if (stored != null) {
                Base64.decode(stored, Base64.NO_WRAP)
            } else {
                ByteArray(32).also {
                    SecureRandom().nextBytes(it)
                    prefs.edit().putString(KEY, Base64.encodeToString(it, Base64.NO_WRAP)).commit()
                }
            }
            cached = key
            return key
        }
    }

    private fun tag(key: ByteArray, payload: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(payload.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    /** [payload] with its seal, to travel in a notice. */
    fun seal(context: Context, payload: String): String =
        payload + MARK + tag(key(context), payload)

    /** The payload [sealed] carries, or null when its seal doesn't check. */
    fun open(context: Context, sealed: String?): String? {
        if (sealed == null) return null
        val at = sealed.lastIndexOf(MARK)
        if (at < 0) return null
        val payload = sealed.substring(0, at)
        val given = sealed.substring(at + MARK.length).toByteArray(Charsets.UTF_8)
        val expected = tag(key(context), payload).toByteArray(Charsets.UTF_8)
        return if (MessageDigest.isEqual(given, expected)) payload else null
    }
}
