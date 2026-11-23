package mail.piuma.piuma_mail

/** A notice in the shade, as [LockedNotices] sees it. */
internal data class ShownNotice(
    val tag: String?,
    val id: Int,
    val channel: String?,
    val category: String?,
)

/** What [LockedNotices] needs of Android's NotificationManager; a fake in tests. */
internal interface Shade {
    /** This app's notices shown now. */
    fun shown(): List<ShownNotice>

    fun cancel(tag: String?, id: Int)

    /** Makes the mail channels, when they aren't there yet. */
    fun ensureChannels()

    /** Posts, or replaces, the one notice that stands for the mail ([LockedNotices.TAG]), on [channel]. */
    fun postStandIn(channel: String)
}

/**
 * While the app lock is turned on in Settings, locked or not, no notice
 * says anything about an email: new mail shows one stand-in that says only
 * "New messages", with no buttons, and opens the app. It is always the
 * same notice ([TAG], [ID]), however many senders wrote.
 *
 * The notices with mail shown before the lock was turned on are cancelled
 * then ([clear]), once; they are never shown again blank in place (Android
 * sheds updates to shown notices beyond five a second, but not cancels).
 */
internal object LockedNotices {
    /** The stand-in's tag; with [ID], a key no email's notice has (they have no tag). */
    const val TAG = "mail.piuma.locked"
    const val ID = 1

    // Background.kt's channels (the Flutter plugin posts on "mail" too).
    const val MAIL_CHANNEL = "mail"
    const val QUIET_CHANNEL = "mail_quiet"

    // Notification.CATEGORY_EMAIL / _REMINDER.
    private val CATEGORIES = setOf("email", "reminder")

    /**
     * A notice about mail: the background service's and the Flutter
     * plugin's, on the mail channels. Sign-in problems (an account's name,
     * category "err") and "Couldn't do that" (no category) are not, nor is
     * the stand-in.
     */
    fun isMail(n: ShownNotice): Boolean =
        n.channel in setOf(MAIL_CHANNEL, QUIET_CHANNEL) && n.category in CATEGORIES && !(n.tag == TAG && n.id == ID)

    /** Cancels every notice about mail shown now; how many went. */
    fun clear(shade: Shade): Int {
        val mail = try {
            shade.shown().filter(::isMail)
        } catch (e: Exception) {
            // The system's list could not be read: nothing to cancel.
            emptyList()
        }
        for (n in mail) shade.cancel(n.tag, n.id)
        return mail.size
    }

    /**
     * New mail while the lock is on: one stand-in for the whole batch, on
     * a channel made first (Android drops a notice whose channel isn't
     * there), [quiet] when all of it came in the quiet hours. A notice
     * with mail still shown, posted just as the lock was turned on, goes.
     */
    fun show(shade: Shade, quiet: Boolean) {
        clear(shade)
        shade.ensureChannels()
        shade.postStandIn(if (quiet) QUIET_CHANNEL else MAIL_CHANNEL)
    }
}
