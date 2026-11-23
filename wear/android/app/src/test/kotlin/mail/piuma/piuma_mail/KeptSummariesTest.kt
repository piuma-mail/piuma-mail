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
        assertEquals("new", KeptSummaries.pick(listOf(old, now), setOf("new-phone")))
    }

    @Test
    fun withNoPhoneConnectedTheNewestWins() {
        val old = KeptSummary("old-phone", "old", at = 1_000, locked = true)
        val now = KeptSummary("new-phone", "new", at = 2_000, locked = false)
        assertEquals("new", KeptSummaries.pick(listOf(old, now), emptySet()))
        // Made in the same second: the locked one.
        val locked = KeptSummary("new-phone", "locked", at = 2_000, locked = true)
        assertEquals("locked", KeptSummaries.pick(listOf(now, locked), emptySet()))
    }

    @Test
    fun nothingKept() {
        assertNull(KeptSummaries.pick(emptyList(), setOf("phone")))
    }
}
