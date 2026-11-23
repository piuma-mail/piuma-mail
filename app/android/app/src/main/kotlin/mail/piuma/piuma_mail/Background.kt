package mail.piuma.piuma_mail

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** The engine's calls for the background (`rust/src/android.rs`). */
object MailNative {
    init {
        System.loadLibrary("piuma_bridge")
    }

    /** Opens the engine; the accounts' ids, comma separated, or "". */
    @JvmStatic external fun open(context: Context, dbPath: String): String

    @JvmStatic external fun remember(accountId: Long, password: String)

    /** Follows every account, keeping the notices for [next]. */
    @JvmStatic external fun start()

    /** The notices that came, as JSON, waiting at most [timeoutMs]. */
    @JvmStatic external fun next(minute: Int, timeoutMs: Long): String

    /** One look at every inbox; the notices as JSON. */
    @JvmStatic external fun checkOnce(minute: Int): String

    /** Sends what waits in the outbox, once. */
    @JvmStatic external fun sendOutbox()

    /** The device moved to another network: connections start over. */
    @JvmStatic external fun networkChanged()

    /**
     * A notice's button: "archive", "snooze" until [until] (Unix seconds)
     * or "reply" with [text]. False when it could not be done.
     */
    @JvmStatic external fun act(payload: String, action: String, until: Long, text: String): Boolean
    /** The Vault notices due now, as JSON like [next]'s. */
    @JvmStatic external fun reminders(offsetMinutes: Int, minute: Int): String

    /** The accounts whose password was refused, as JSON, each given once. */
    @JvmStatic external fun signInNotices(): String

    /** The browser came back from an OAuth sign-in page with this address. */
    @JvmStatic external fun oauthRedirect(url: String): Boolean

    /**
     * Secrets the engine got (an OAuth sign-in, a renewed refresh token)
     * for the Keystore, as JSON `{"claim", "secrets": [{"key", "value",
     * "seq"}]}`: claim 0 and none while the app writes them. Hand the
     * claim back to [secretsWritten] once written.
     */
    @JvmStatic external fun keptSecrets(): String

    /**
     * The secrets of [claim] now in the Keystore, one `key=seq` a line;
     * the engine keeps the others for the next try.
     */
    @JvmStatic external fun secretsWritten(claim: Long, written: String)

    /** The inbox as a paired watch shows it, as JSON (`watch.rs`). */
    @JvmStatic external fun watchSummary(): String

    /** The words of the email [payload] names, for the watch, as JSON. */
    @JvmStatic external fun watchText(payload: String, offsetMinutes: Int): String
}

/**
 * Tells the engine when the device moves to another network (Wi-Fi to
 * mobile data and back), so a connection that died on the way is opened
 * again at once, not after a timeout. Follows for the life of the process.
 */
object NetworkWatch {
    @Volatile private var following = false

    fun follow(context: Context) {
        if (following) return
        following = true
        val manager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        try {
            follow(manager)
        } catch (e: Exception) {
            // Without it, a dead connection waits for its timeout instead.
        }
    }

    /** The kind of network in use, as a report names it. */
    fun kind(context: Context): String {
        val manager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        val caps = try {
            manager?.getNetworkCapabilities(manager.activeNetwork)
        } catch (e: Exception) {
            null
        } ?: return "offline"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "other"
        }
    }

    private fun follow(manager: ConnectivityManager) {
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            private var current: Network? = null
            private var blocked = false

            override fun onAvailable(network: Network) {
                // The first call names the network we already have.
                val moved = current != null && current != network
                current = network
                if (moved) MailNative.networkChanged()
            }

            // Android cuts an app in the background off the network (Doze,
            // app standby, data saver) and lets it back when it comes to
            // the front: the watchers try again at once, instead of after
            // the waits their failures meanwhile grew to, with "You're
            // offline" shown all along (Android 10 and later).
            override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
                val unblocked = this.blocked && !blocked
                this.blocked = blocked
                if (unblocked) MailNative.networkChanged()
            }
        })
    }
}

/**
 * How new mail reaches the phone with the app closed (`AndroidBackground`):
 * "instant" keeps [MailService] running, "periodic" looks every 15
 * minutes with [CheckJob]. Unset until the person picks, after the first
 * account.
 */
object Background {
    const val INSTANT = "instant"
    const val PERIODIC = "periodic"
    private const val JOB = 1
    // One outbox job per message: its id after this offset, so no two
    // waiting messages share a job (a later one would replace the other).
    private const val OUTBOX_JOB = 1000L
    private const val MAIL_CHANNEL = "mail"
    // Quiet hours: shown in the shade, without a sound.
    private const val QUIET_CHANNEL = "mail_quiet"
    private const val PAYLOAD = "mail.piuma.payload"

    /** The stand-in's intent ([LockedNotices]): no PendingIntent of a notice for one email matches it. */
    private const val OPEN_LOCKED = "mail.piuma.open_locked"

    private fun prefs(context: Context) =
        context.getSharedPreferences("background", Context.MODE_PRIVATE)

    fun mode(context: Context): String? = prefs(context).getString("mode", null)

    /** Keeps the choice and starts what it needs. */
    fun setMode(context: Context, mode: String) {
        prefs(context).edit().putString("mode", mode).apply()
        apply(context)
    }

    /** Starts what the choice needs: at app start, and after a reboot. */
    fun apply(context: Context) {
        val jobs = context.getSystemService(JobScheduler::class.java)
        when (mode(context)) {
            INSTANT -> {
                jobs.cancel(JOB)
                MailService.start(context)
            }
            PERIODIC -> {
                context.stopService(Intent(context, MailService::class.java))
                val job = JobInfo.Builder(JOB, ComponentName(context, CheckJob::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(15 * 60 * 1000L)
                    .setPersisted(true)
                    .build()
                if (jobs.getPendingJob(JOB) == null) jobs.schedule(job)
            }
        }
    }

    /** The job of outbox message [id]; null past what a job id can hold. */
    private fun outboxJob(id: Long): Int? =
        (OUTBOX_JOB + id).takeIf { id >= 0 && it <= Int.MAX_VALUE }?.toInt()

    /**
     * Sends outbox message [id] at [atSeconds] (Unix seconds), once the
     * phone is online, whether or not the app is still open.
     */
    fun outboxAt(context: Context, id: Long, atSeconds: Long) {
        // Beyond two billion messages it goes at the app's next start.
        val jobId = outboxJob(id) ?: return
        val jobs = context.getSystemService(JobScheduler::class.java)
        val wait = (atSeconds * 1000L - System.currentTimeMillis()).coerceAtLeast(0L)
        val job = JobInfo.Builder(jobId, ComponentName(context, OutboxJob::class.java))
            .setMinimumLatency(wait)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .build()
        jobs.schedule(job)
    }

    /** Message [id] left the outbox (taken back with Undo, deleted): its job goes. */
    fun cancelOutbox(context: Context, id: Long) {
        val jobId = outboxJob(id) ?: return
        context.getSystemService(JobScheduler::class.java).cancel(jobId)
    }

    /** Opens the engine with every password; how many accounts it has. */
    fun openEngine(context: Context): Int {
        // Where main.dart opens it: getApplicationSupportDirectory().
        val db = context.filesDir.path + "/piuma.db"
        val ids = MailNative.open(context, db).split(',').filter { it.isNotEmpty() }
        val passwords = Passwords(context)
        for (id in ids) {
            val password = try {
                passwords.read("account-$id")
            } catch (e: Exception) {
                null
            } ?: continue
            MailNative.remember(id.toLong(), password)
        }
        return ids.size
    }

    /**
     * Puts the secrets the engine got in the Keystore. The engine hands
     * them to one writer at a time (this or the app) and drops each only
     * once the write went through, so the newest one always lands last.
     */
    fun keepSecrets(context: Context) {
        val claim: Long
        val kept: JSONArray
        try {
            val json = JSONObject(MailNative.keptSecrets())
            claim = json.getLong("claim")
            kept = json.getJSONArray("secrets")
        } catch (e: Exception) {
            return
        }
        if (claim == 0L) return
        val written = StringBuilder()
        try {
            val passwords = Passwords(context)
            for (i in 0 until kept.length()) {
                val k = kept.getJSONObject(i)
                try {
                    passwords.write(k.getString("key"), k.getString("value"))
                    written.append(k.getString("key")).append('=').append(k.getLong("seq")).append('\n')
                } catch (e: Exception) {
                    // Stays in the engine for the next try; the old token still works.
                }
            }
        } finally {
            MailNative.secretsWritten(claim, written.toString())
        }
    }

    /** The Vault notices due now, and "While you were away", where the phone is. */
    fun reminders(): String {
        val offset = java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60_000
        return MailNative.reminders(offset, minute())
    }

    /** Minutes since Monday 00:00, local time, for the quiet hours. */
    fun minute(): Int {
        val now = Calendar.getInstance()
        val weekday = (now.get(Calendar.DAY_OF_WEEK) + 5) % 7
        return weekday * 24 * 60 + now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
    }

    /**
     * Shows the engine's notices: one per sender, opening its message.
     * While the app lock is on, only the stand-in ([LockedNotices]): no
     * sender, subject, preview or buttons, here or on a watch the notice
     * reaches. Synchronized with [blankNotices], so the lock turning on
     * can't fold the shade while a notice with mail in it is still on its
     * way there. Never called on the main thread: it waits on the system.
     */
    @Synchronized
    fun show(context: Context, json: String) {
        val notices = try {
            JSONArray(json)
        } catch (e: Exception) {
            return
        }
        if (notices.length() == 0) return
        val manager = channels(context)
        val silent = (0 until notices.length()).all { notices.getJSONObject(it).optBoolean("silent", false) }
        for (i in 0 until notices.length()) {
            // Checked for each, just before it is made and again just
            // before it goes: the lock may be turned on meanwhile.
            if (AppLockFile.on(context)) {
                showLocked(context, manager, silent)
                break
            }
            val n = notices.getJSONObject(i)
            val id = n.getInt("id")
            val count = n.getInt("count")
            val sender = n.getString("sender")
            val vault = n.optJSONObject("vault")
            val away = n.optJSONObject("away")
            val noReply = n.optJSONObject("noReply")
            val title = when {
                away != null -> context.getString(R.string.notice_away_title)
                noReply != null -> noReplyTitle(context, sender, noReply)
                vault != null -> vaultTitle(context, vault)
                count > 1 -> context.resources.getQuantityString(R.plurals.notice_title_many, count, sender, count)
                else -> sender
            }
            val subject = when {
                away != null -> awayDetail(context, away)
                vault != null -> vaultDetail(context, vault)
                else -> n.getString("subject")
            }
            val preview = n.getString("preview")
            val body = listOf(subject, preview).filter { it.isNotEmpty() }.joinToString("\n")
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(PAYLOAD, NoticeSeal.seal(context, n.getString("payload")))
            val tap = PendingIntent.getActivity(
                context,
                id,
                open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val quiet = n.getBoolean("silent")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, if (quiet) QUIET_CHANNEL else MAIL_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).apply {
                    if (!quiet) setDefaults(Notification.DEFAULT_ALL)
                }
            }
            // One email: Reply, Archive and Snooze, as on `Notifications`.
            // A notice for several leaves them out, since each would only
            // touch the newest. A Vault notice is about a card, so it has none.
            if (count == 1 && vault == null && away == null && noReply == null) {
                NoticeActions.add(context, builder, id, n.getString("payload"), sender, n.optInt("others", 0))
            }
            builder
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(context.getColor(R.color.ic_launcher_background))
                .setContentTitle(title)
                .setContentText(subject.ifEmpty { preview })
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(if (vault != null || noReply != null) Notification.CATEGORY_REMINDER else Notification.CATEGORY_EMAIL)
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
            // "Piuma Mail · Vault", as on the board.
            if (vault != null) builder.setSubText(context.getString(R.string.vault_notice_label))
            val notice = builder.build()
            if (AppLockFile.on(context)) {
                showLocked(context, manager, silent)
                break
            }
            try {
                manager.notify(id, notice)
            } catch (e: SecurityException) {
                // Notifications not allowed: the mail is still there.
            }
        }
        // A paired watch lists the new mail too (`WatchWearOS`).
        WatchLink.publish(context)
    }

    /** "12 emails, 3 from people: Sara Conti, Luca Bianchi, Dad". */
    private fun awayDetail(context: Context, away: org.json.JSONObject): String {
        val emails = away.getInt("emails")
        val people = away.getInt("people")
        val r = context.resources
        val all = r.getQuantityString(R.plurals.notice_away_emails, emails, emails)
        if (people == 0) return all
        val names = away.getJSONArray("names")
        val who = (0 until names.length()).joinToString(", ") { names.getString(it) }
        val from = r.getQuantityString(R.plurals.notice_away_people, people, people)
        return if (who.isEmpty()) "$all, $from" else "$all, $from: $who"
    }

    /**
     * "Tell me when it can't sign in" with the app closed: "Work can't
     * sign in", once, opening the account's details.
     */
    @Synchronized
    fun showSignIn(context: Context) {
        val notices = try {
            JSONArray(MailNative.signInNotices())
        } catch (e: Exception) {
            return
        }
        if (notices.length() == 0) return
        val manager = channels(context)
        for (i in 0 until notices.length()) {
            val n = notices.getJSONObject(i)
            val id = n.getInt("id")
            if (n.optBoolean("cancel", false)) {
                manager.cancel(id)
                continue
            }
            val body = context.getString(
                if (n.optBoolean("certificate", false)) {
                    R.string.notice_sign_in_certificate
                } else {
                    R.string.notice_sign_in_body
                },
            )
            val tap = PendingIntent.getActivity(
                context,
                id,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(PAYLOAD, NoticeSeal.seal(context, n.getString("payload"))),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, MAIL_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setDefaults(Notification.DEFAULT_ALL)
            }
            builder
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(context.getColor(R.color.ic_launcher_background))
                .setContentTitle(context.getString(R.string.notice_sign_in_title, n.getString("name")))
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_ERROR)
                .setContentIntent(tap)
                .setAutoCancel(true)
            try {
                manager.notify(id, builder.build())
            } catch (e: SecurityException) {
                // Notifications not allowed: the app says it when opened.
            }
        }
    }

    /**
     * New mail while the app lock is on: any notice for one email still
     * shown goes, and the stand-in says "New messages", with a sound
     * unless all of it came in the quiet hours.
     */
    private fun showLocked(context: Context, manager: NotificationManager, silent: Boolean) {
        LockedNotices.fold(SystemShade(context, manager))
        postStandIn(context, manager, if (silent) QUIET_CHANNEL else MAIL_CHANNEL, alert = true)
    }

    /**
     * The app lock was turned on or closed: every mail notice already shown
     * (this service's and the Flutter plugin's, on the same channels) is
     * cancelled, and one stand-in that says only "New messages", with no
     * buttons, takes their place, silently ([LockedNotices]). Tapping it
     * opens the app, at its lock screen. Sign-in problem notices name an
     * account, not mail, and stay as they are.
     *
     * Returns at once: the work waits on the system (and on [show], which
     * may be posting), so it runs on [worker], never on the caller's
     * thread, which is often the main one.
     */
    fun blankNotices(context: Context) {
        val app = context.applicationContext
        worker.post { foldShown(app) }
        // Once more a moment later: a notice posted just before (by [show]
        // or the Flutter plugin) may still be on its way into the list the
        // system gives back.
        worker.postDelayed({ foldShown(app) }, AGAIN_MS)
    }

    /** [showSignIn] off the caller's thread, as [blankNotices]. */
    fun showSignInLater(context: Context) {
        val app = context.applicationContext
        worker.post { showSignIn(app) }
    }

    /** One thread for the notice work asked from the main thread, in order. */
    private val worker by lazy {
        Handler(HandlerThread("piuma-notices").apply { start() }.looper)
    }
    private const val AGAIN_MS = 1_000L

    @Synchronized
    private fun foldShown(context: Context) {
        if (!AppLockFile.on(context)) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            LockedNotices.fold(SystemShade(context, manager))
        } catch (e: Exception) {
            // The system's list could not be read: nothing more to do.
        }
    }

    /** The stand-in ([LockedNotices]) on [channel]; [alert] false for one only folding the shade. */
    private fun postStandIn(context: Context, manager: NotificationManager, channel: String, alert: Boolean) {
        val tap = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .setAction(OPEN_LOCKED)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notice = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(context.getColor(R.color.ic_launcher_background))
            .setContentTitle(AppLockFile.notice(context))
            .setCategory(Notification.CATEGORY_EMAIL)
            .setContentIntent(tap)
            .setShowWhen(true)
            .setAutoCancel(true)
            .setOnlyAlertOnce(!alert)
            .build()
        try {
            manager.notify(LockedNotices.TAG, LockedNotices.ID, notice)
        } catch (e: SecurityException) {
            // Notifications not allowed any more: nothing is shown.
        }
    }

    /** Android's shade, for [LockedNotices.fold]. */
    private class SystemShade(
        private val context: Context,
        private val manager: NotificationManager,
    ) : Shade {
        override fun shown(): List<ShownNotice> = manager.activeNotifications.map {
            ShownNotice(it.tag, it.id, it.notification.channelId, it.notification.category)
        }

        override fun cancel(tag: String?, id: Int) = manager.cancel(tag, id)

        override fun postStandIn() = postStandIn(context, manager, QUIET_CHANNEL, alert = false)
    }

    /** The two mail channels, made the first time. */
    private fun channels(context: Context): NotificationManager {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(MAIL_CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    MAIL_CHANNEL,
                    context.getString(R.string.notice_channel),
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(QUIET_CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    QUIET_CHANNEL,
                    context.getString(R.string.notice_quiet_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        return manager
    }

    /** "No reply from Luca · sent 3 days ago", as the inbox row says it. */
    private fun noReplyTitle(context: Context, name: String, r: org.json.JSONObject): String {
        val days = r.optInt("sentDaysAgo", 0)
        val sent = when {
            days <= 0 -> context.getString(R.string.remind_sent_today)
            days == 1 -> context.getString(R.string.remind_sent_yesterday)
            else -> context.resources.getQuantityString(R.plurals.remind_sent_days_ago, days, days)
        }
        return context.getString(R.string.remind_no_reply, name) + " · " + sent
    }

    /** "Your package arrives today · Corriere Rapido", "Due in 3 days · Enel". */
    private fun vaultTitle(context: Context, v: org.json.JSONObject): String {
        val merchant = v.optString("merchant")
        val due = v.optInt("dueIn", -1)
        val what = when {
            due < 0 -> context.getString(R.string.vault_notice_parcel)
            due == 0 -> context.getString(R.string.vault_notice_due_today)
            due == 1 -> context.getString(R.string.vault_notice_due_tomorrow)
            else -> context.resources.getQuantityString(R.plurals.vault_notice_due_in, due, due)
        }
        return if (merchant.isEmpty()) what else "$what · $merchant"
    }

    /** "Desk lamp · around 10:00", "€62.40 · Electricity bill". */
    private fun vaultDetail(context: Context, v: org.json.JSONObject): String {
        val title = v.optString("title")
        val time = v.optString("time")
        val amount = v.optLong("amount", -1)
        val first = if (v.optInt("dueIn", -1) < 0) {
            if (time.isEmpty()) "" else context.getString(R.string.vault_notice_around, time)
        } else if (amount >= 0) {
            money(amount, v.optString("currency"))
        } else {
            ""
        }
        val parts = if (v.optInt("dueIn", -1) < 0) listOf(title, first) else listOf(first, title)
        return parts.filter { it.isNotEmpty() }.joinToString(" · ")
    }

    private fun money(cents: Long, currency: String): String {
        val format = java.text.NumberFormat.getCurrencyInstance()
        try {
            if (currency.isNotEmpty()) format.currency = java.util.Currency.getInstance(currency)
        } catch (e: IllegalArgumentException) {
            // An unknown code: the phone's own currency sign, then.
        }
        return format.format(cents / 100.0)
    }

    /**
     * The message a notice was opened for, if it was: only a payload this
     * app sealed, never one another app put in an intent.
     */
    fun payload(context: Context, intent: Intent?): String? =
        NoticeSeal.open(context, intent?.getStringExtra(PAYLOAD))
}
