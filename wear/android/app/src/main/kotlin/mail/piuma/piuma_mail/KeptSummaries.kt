package mail.piuma.piuma_mail

/** A summary the Data Layer keeps, from the phone [node], made at [at] (Unix seconds). */
internal data class KeptSummary(val node: String?, val json: String, val at: Long, val locked: Boolean)

internal object KeptSummaries {
    /**
     * Which kept summary the watch shows as it starts, before the phone
     * answers: the Data Layer keeps the last one of every phone that sent
     * one (each phone puts it at the same path, replacing its own). The
     * one from a phone connected now comes first, then the newest one the
     * phone made, then a locked one. Generations only count within one
     * phone install, so they don't order these; the phone's fresh summary
     * replaces this one as soon as it comes (`link.dart`).
     */
    fun pick(kept: List<KeptSummary>, connected: Set<String>): String? =
        kept.maxWithOrNull(compareBy<KeptSummary>({ it.node in connected }, { it.at }, { it.locked }))?.json
}
