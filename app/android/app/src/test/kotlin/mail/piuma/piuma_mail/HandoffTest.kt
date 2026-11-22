package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A cold start with a `mailto:` link, a share or an email file: the intent
 * comes in `onCreate`, before the engine (and `Shared`) is attached.
 */
class HandoffTest {
    @Test
    fun keepsWhatComesBeforeTheTakerAndHandsItOverInOrder() {
        val handoff = Handoff<String>()
        handoff.offer("mailto:a@example.com")
        handoff.offer("share")
        assertEquals(2, handoff.pending)
        val got = mutableListOf<String>()
        handoff.attach { got.add(it) }
        assertEquals(listOf("mailto:a@example.com", "share"), got)
        assertEquals(0, handoff.pending)
        handoff.offer("eml")
        assertEquals(listOf("mailto:a@example.com", "share", "eml"), got)
    }

    @Test
    fun waitsAgainOnceTheTakerIsGone() {
        val handoff = Handoff<String>()
        val first = mutableListOf<String>()
        handoff.attach { first.add(it) }
        handoff.detach()
        handoff.offer("later")
        assertEquals(emptyList<String>(), first)
        val second = mutableListOf<String>()
        handoff.attach { second.add(it) }
        assertEquals(listOf("later"), second)
    }

    @Test
    fun keepsAtMostMax() {
        val handoff = Handoff<Int>(max = 3)
        repeat(10) { handoff.offer(it) }
        val got = mutableListOf<Int>()
        handoff.attach { got.add(it) }
        assertEquals(listOf(0, 1, 2), got)
    }
}
