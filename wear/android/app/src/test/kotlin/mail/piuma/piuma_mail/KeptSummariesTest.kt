package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The summary the watch shows as it starts, of those the Data Layer kept. */
class KeptSummariesTest {
    @Test
    fun theConnectedPhonesComesFirst() {
        val old = KeptSummary("old-phone", "old", at = 2_000, locked = false)
        val now = KeptSummary("new-phone", "new", at = 1_000, locked = false)
        // The earlier phone's clock ran ahead: still the connected one's.
        assertEquals("new", KeptSummaries.pick(listOf(old, now), setOf("new-phone"))?.json)
        // Connected, but it kept nothing: not the other phone's mail.
        assertNull(KeptSummaries.pick(listOf(old), setOf("new-phone")))
    }

    @Test
    fun offlineALockedOneWinsOverAnyMail() {
        val locked = KeptSummary("old-phone", "locked", at = 1_000, locked = true)
        val now = KeptSummary("new-phone", "new", at = 2_000, locked = false)
        assertEquals("locked", KeptSummaries.pick(listOf(now, locked), emptySet())?.json)
        // Also over the connected phone's own, newer one.
        assertEquals("locked", KeptSummaries.pick(listOf(now, locked), setOf("new-phone"))?.json)
        // With nothing locked, the newest.
        val older = KeptSummary("old-phone", "old", at = 1_000, locked = false)
        assertEquals("new", KeptSummaries.pick(listOf(older, now), emptySet())?.json)
    }

    @Test
    fun nothingKept() {
        assertNull(KeptSummaries.pick(emptyList(), setOf("phone")))
    }
}
