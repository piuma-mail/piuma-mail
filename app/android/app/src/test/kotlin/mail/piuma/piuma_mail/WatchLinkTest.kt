package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** The epoch and generation the watch uses to order the summaries. */
class WatchLinkTest {
    private val epoch = "0f8c2a1e-5b7d-4c3a-9e21-6d4b8f0a7c55"

    @Test
    fun generationsOnlyGrow() {
        assertEquals(1_700_000_000_000L, WatchLink.nextGeneration(5L, 1_700_000_000_000L))
        // The clock set back: still after the last one.
        assertEquals(1_700_000_000_001L, WatchLink.nextGeneration(1_700_000_000_000L, 1_000L))
        // Two in the same millisecond.
        assertEquals(1_700_000_000_001L, WatchLink.nextGeneration(1_700_000_000_000L, 1_700_000_000_000L))
    }

    @Test
    fun stampsTheEpochAndGenerationOnTheSummary() {
        assertEquals(
            """{"epoch":"$epoch","gen":42,"at":7,"locked":true,"accounts":[],"rows":[],"templates":[]}""",
            WatchLink.stamp("""{"at":7,"locked":true,"accounts":[],"rows":[],"templates":[]}""", epoch, 42L),
        )
        assertEquals("""{"epoch":"$epoch","gen":3}""", WatchLink.stamp(" { } ", epoch, 3L))
        assertTrue(WatchLink.stamp("""{"at":1}""", epoch, 9L).startsWith("""{"epoch":"$epoch","gen":9,"""))
    }

    @Test
    fun refusesWhatIsNotAnObject() {
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("", epoch, 1L) }
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("[1]", epoch, 1L) }
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("{}", "a\"b", 1L) }
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("{}", "", 1L) }
    }
}
