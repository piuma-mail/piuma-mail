package mail.piuma.piuma_mail

/**
 * Holds what arrives before there is anyone to take it, and hands it over,
 * in order, once there is. MainActivity's intents (a `mailto:` link, a
 * share, an email file) come in `onCreate`, while a FlutterFragmentActivity
 * attaches its engine, and with it [Shared], only later.
 */
internal class Handoff<T>(private val max: Int = 8) {
    private var taker: ((T) -> Unit)? = null
    private val waiting = ArrayDeque<T>()

    /** Hands [item] over now, or keeps it (at most [max]) until [attach]. */
    fun offer(item: T) {
        val take = taker
        if (take != null) {
            take(item)
        } else if (waiting.size < max) {
            waiting.addLast(item)
        }
    }

    /** From now on [take] gets every item, first those kept so far. */
    fun attach(take: (T) -> Unit) {
        taker = take
        while (waiting.isNotEmpty()) take(waiting.removeFirst())
    }

    /** The taker is gone (the engine detached): items wait again. */
    fun detach() {
        taker = null
    }

    val pending: Int get() = waiting.size
}
