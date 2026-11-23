package mail.piuma.piuma_mail

/** A notice in the shade, as [LockedNotices.fold] sees it. */
internal data class ShownNotice(
    val tag: String?,
    val id: Int,
    val channel: String?,
    val category: String?,
)

/** What [LockedNotices.fold] needs of Android's NotificationManager; a fake in tests. */
internal interface Shade {
    /** This app's notices shown now. */
    fun shown(): List<ShownNotice>

    fun cancel(tag: String?, id: Int)

    /** Posts, or replaces, the one notice that stands for the mail ([LockedNotices.TAG]). */
    fun postStandIn()
}

/**
 * While the app lock is on, the shade holds no notice about a single
 * email: they all fold into one stand-in that says only "New messages",
 * with no buttons, and opens the app at its lock screen.
 *
 * The notices already shown are cancelled, never shown again blank in
 * place: Android sheds updates to a shown notice beyond five a second per
 * app (`NotificationManagerService.checkDisqualifyingFeatures`, which
 * rate-limits only a post whose key is already shown), so blanking a full
 * shade in place silently leaves some with their sender and subject.
 * Cancelling has no such limit. Only the stand-in is ever updated, and an
 * update of it that is shed loses nothing: it never has mail on it.
 */
internal object LockedNotices {
    /** The stand-in's tag; with [ID], a key no email's notice has (they have no tag). */
    const val TAG = "mail.piuma.locked"
    const val ID = 1

    // Background.kt's channels and Notification.CATEGORY_EMAIL / _REMINDER.
    private val CHANNELS = setOf("mail", "mail_quiet")
    private val CATEGORIES = setOf("email", "reminder")

    /**
     * A notice about mail: the background service's and the Flutter
     * plugin's, on the mail channels. Sign-in problems (an account's name,
     * category "err") and "Couldn't do that" (no category) are not.
     */
    fun isMail(n: ShownNotice): Boolean =
        n.channel in CHANNELS && n.category in CATEGORIES && !(n.tag == TAG && n.id == ID)

    /**
     * Cancels every mail notice shown, then posts the stand-in when any
     * went. True when any went.
     */
    fun fold(shade: Shade): Boolean {
        val mail = shade.shown().filter(::isMail)
        for (n in mail) shade.cancel(n.tag, n.id)
        if (mail.isNotEmpty()) shade.postStandIn()
        return mail.isNotEmpty()
    }
}
