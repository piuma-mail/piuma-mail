package mail.piuma.piuma_mail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** The generation the watch uses to drop a summary that arrives late. */
class WatchLinkTest {
    @Test
    fun generationsOnlyGrow() {
        assertEquals(1_700_000_000_000L, WatchLink.nextGeneration(5L, 1_700_000_000_000L))
        // The clock set back: still after the last one.
        assertEquals(1_700_000_000_001L, WatchLink.nextGeneration(1_700_000_000_000L, 1_000L))
        // Two in the same millisecond.
        assertEquals(1_700_000_000_001L, WatchLink.nextGeneration(1_700_000_000_000L, 1_700_000_000_000L))
    }

    @Test
    fun stampsTheGenerationOnTheSummary() {
        assertEquals(
            """{"gen":42,"at":7,"locked":true,"accounts":[],"rows":[],"templates":[]}""",
            WatchLink.stamp("""{"at":7,"locked":true,"accounts":[],"rows":[],"templates":[]}""", 42L),
        )
        assertEquals("""{"gen":3}""", WatchLink.stamp(" { } ", 3L))
        assertTrue(WatchLink.stamp("""{"at":1}""", 9L).startsWith("""{"gen":9,"""))
    }

    @Test
    fun refusesWhatIsNotAnObject() {
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("", 1L) }
        assertThrows(IllegalArgumentException::class.java) { WatchLink.stamp("[1]", 1L) }
    }
}
