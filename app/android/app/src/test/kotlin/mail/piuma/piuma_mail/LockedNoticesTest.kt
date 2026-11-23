package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A shade as Android keeps it: a notice posted on a channel that isn't
 * there is dropped without a word, as AOSP does; [log] has the calls in
 * order.
 */
private class FakeShade : Shade {
    /** Key ("tag/id") to the notice and what it says. */
    val shown = linkedMapOf<String, Pair<ShownNotice, String>>()
    val channels = mutableSetOf<String>()
    val log = mutableListOf<String>()

    fun post(n: ShownNotice, text: String) {
        if (n.channel !in channels && n.channel != "service") return
        shown["${n.tag}/${n.id}"] = n to text
    }

    override fun shown(): List<ShownNotice> = shown.values.map { it.first }

    override fun cancel(tag: String?, id: Int) {
        log += "cancel $tag/$id"
        shown.remove("$tag/$id")
    }

    override fun ensureChannels() {
        log += "channels"
        channels += setOf("mail", "mail_quiet")
    }

    override fun postStandIn(channel: String) {
        log += "standIn $channel"
        post(ShownNotice(LockedNotices.TAG, LockedNotices.ID, channel, "email"), "New messages")
    }

    /** What the shade shows that names a sender or subject. */
    fun withMail(): List<String> = shown.values.map { it.second }.filter { it.startsWith("From ") }
}

private fun email(id: Int, channel: String = "mail") = ShownNotice(null, id, channel, "email")

class LockedNoticesTest {
    @Test
    fun turningTheLockOnCancelsEveryMailNotice() {
        val shade = FakeShade()
        shade.ensureChannels()
        repeat(32) { shade.post(email(it, if (it % 3 == 0) "mail_quiet" else "mail"), "From sender $it: subject") }
        shade.post(ShownNotice(null, 100, "mail", "reminder"), "From Enel: due in 3 days")
        // A sign-in problem names an account, "Couldn't do that" nothing.
        shade.post(ShownNotice(null, 200, "mail", "err"), "Work can't sign in")
        shade.post(ShownNotice(null, 201, "mail_quiet", null), "Couldn't do that")
        // The background service's own notice, on its channel.
        shade.post(ShownNotice(null, 300, "service", "service"), "Checking mail")

        assertEquals(33, LockedNotices.clear(shade))

        assertEquals(emptyList<String>(), shade.withMail())
        assertEquals(
            listOf("Work can't sign in", "Couldn't do that", "Checking mail"),
            shade.shown.values.map { it.second },
        )
        // Nothing to bring back: no stand-in is posted for what went.
        assertTrue(shade.log.none { it.startsWith("standIn") })
    }

    @Test
    fun twoSendersShowOneNoticeWithoutMail() {
        val shade = FakeShade()
        // What the background service hands over while the lock is on,
        // unlocked or not: one batch with two senders.
        LockedNotices.show(shade, quiet = false)
        LockedNotices.show(shade, quiet = false)
        assertEquals(listOf("New messages"), shade.shown.values.map { it.second })
        assertEquals(LockedNotices.TAG, shade.shown().single().tag)
        assertEquals(LockedNotices.ID, shade.shown().single().id)
    }

    @Test
    fun theChannelIsMadeBeforeTheStandInGoes() {
        // A fresh install: no channel yet, so a post before it is lost.
        val shade = FakeShade()
        LockedNotices.show(shade, quiet = true)
        assertEquals(listOf("channels", "standIn mail_quiet"), shade.log)
        assertEquals("mail_quiet", shade.shown().single().channel)
    }

    @Test
    fun aMailNoticeLeftOverGoesWithTheNextStandIn() {
        val shade = FakeShade()
        shade.ensureChannels()
        // Posted by the Flutter plugin just as the lock was turned on.
        shade.post(email(7), "From Sara: Print quote")
        shade.log.clear()
        LockedNotices.show(shade, quiet = false)
        assertEquals(listOf("New messages"), shade.shown.values.map { it.second })
        assertEquals(listOf("cancel null/7", "channels", "standIn mail"), shade.log)
    }
}
