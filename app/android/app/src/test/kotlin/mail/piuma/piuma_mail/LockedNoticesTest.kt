package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A shade that sheds updates as Android does: an update to a notice
 * already shown, past [rate] posts in the burst, is dropped without a word
 * (`NotificationManagerService.checkDisqualifyingFeatures`); a new notice
 * and a cancel always go through.
 */
private class SheddingShade(private val rate: Int) : Shade {
    /** Key ("tag/id") to what the notice says. */
    val shown = linkedMapOf<String, Pair<ShownNotice, String>>()
    var posts = 0
    var shed = 0

    fun post(n: ShownNotice, text: String) {
        val key = "${n.tag}/${n.id}"
        posts++
        if (key in shown && posts > rate) {
            shed++
            return
        }
        shown[key] = n to text
    }

    override fun shown(): List<ShownNotice> = shown.values.map { it.first }

    override fun cancel(tag: String?, id: Int) {
        shown.remove("$tag/$id")
    }

    override fun postStandIn() =
        post(ShownNotice(LockedNotices.TAG, LockedNotices.ID, "mail_quiet", "email"), "New messages")

    /** What the shade shows that names a sender or subject. */
    fun withMail(): List<String> = shown.values.map { it.second }.filter { it.startsWith("From ") }
}

private fun email(id: Int, channel: String = "mail") = ShownNotice(null, id, channel, "email")

class LockedNoticesTest {
    @Test
    fun aFullShadeFoldsIntoOneStandIn() {
        val shade = SheddingShade(rate = 5)
        repeat(32) { shade.post(email(it, if (it % 3 == 0) "mail_quiet" else "mail"), "From sender $it: subject") }
        shade.post(ShownNotice(null, 100, "mail", "reminder"), "From Enel: due in 3 days")
        // A sign-in problem names an account, "Couldn't do that" nothing.
        shade.post(ShownNotice(null, 200, "mail", "err"), "Work can't sign in")
        shade.post(ShownNotice(null, 201, "mail_quiet", null), "Couldn't do that")
        // The background service's own notice, on its channel.
        shade.post(ShownNotice(null, 300, "service", "service"), "Checking mail")

        assertTrue(LockedNotices.fold(shade))

        assertEquals(emptyList<String>(), shade.withMail())
        assertEquals(
            listOf("Work can't sign in", "Couldn't do that", "Checking mail", "New messages"),
            shade.shown.values.map { it.second },
        )
    }

    @Test
    fun aShedUpdateOfTheStandInLeavesNoMail() {
        val shade = SheddingShade(rate = 0)
        shade.shown["${LockedNotices.TAG}/${LockedNotices.ID}"] =
            ShownNotice(LockedNotices.TAG, LockedNotices.ID, "mail", "email") to "New messages"
        // Posted by the Flutter plugin just before the lock closed.
        shade.shown["null/7"] = email(7) to "From Sara: Print quote"

        assertTrue(LockedNotices.fold(shade))

        assertEquals(1, shade.shed)
        assertEquals(listOf("New messages"), shade.shown.values.map { it.second })
    }

    @Test
    fun nothingToFoldPostsNothing() {
        val shade = SheddingShade(rate = 5)
        shade.post(ShownNotice(null, 200, "mail", "err"), "Work can't sign in")
        assertFalse(LockedNotices.fold(shade))
        assertEquals(1, shade.posts)
        // Folding again with the stand-in already there touches nothing.
        shade.postStandIn()
        assertFalse(LockedNotices.fold(shade))
        assertEquals(2, shade.posts)
    }

    @Test
    fun blankingInPlaceWouldLeaveMail() {
        // Why the notices are cancelled: updating each one in place, as an
        // earlier version did, loses most updates to the shedding.
        val shade = SheddingShade(rate = 5)
        repeat(32) { shade.post(email(it), "From sender $it: subject") }
        shade.posts = 0
        for (n in shade.shown()) shade.post(n, "New message")
        assertEquals(27, shade.withMail().size)
    }
}
