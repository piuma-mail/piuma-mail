package mail.piuma.piuma_mail

/** A summary the Data Layer keeps, from the phone [node], made at [at] (Unix seconds). */
internal data class KeptSummary(val node: String?, val json: String, val at: Long, val locked: Boolean)

internal object KeptSummaries {
    /**
     * Which kept summary the watch shows as it starts, before the phone
     * answers: the Data Layer keeps the last one of every phone that sent
     * one (each phone puts it at the same path, replacing its own).
     *
     * A locked one, from any phone, comes before any with mail: the app
     * lock may be on, and a summary with mail is never shown over it.
     * Otherwise the newest from a phone connected now; with no phone
     * connected (the watch on its own), the newest one. A phone that is
     * connected but kept nothing gives none: another phone's mail is not
     * shown. The phone's fresh summary follows (`link.dart`).
     */
    fun pick(kept: List<KeptSummary>, connected: Set<String>): KeptSummary? {
        kept.filter { it.locked }.maxByOrNull { it.at }?.let { return it }
        val mail = if (connected.isEmpty()) kept else kept.filter { it.node in connected }
        return mail.maxByOrNull { it.at }
    }
}
