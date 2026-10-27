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
import org.json.JSONArray
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

            override fun onAvailable(network: Network) {
                // The first call names the network we already have.
                val moved = current != null && current != network
                current = network
                if (moved) MailNative.networkChanged()
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
    private const val MAIL_CHANNEL = "mail"
    // Quiet hours: shown in the shade, without a sound.
    private const val QUIET_CHANNEL = "mail_quiet"
    private const val PAYLOAD = "mail.piuma.payload"

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

    /** Shows the engine's notices: one per sender, opening its message. */
    fun show(context: Context, json: String) {
        val notices = try {
            JSONArray(json)
        } catch (e: Exception) {
            return
        }
        if (notices.length() == 0) return
        val manager = channels(context)
        for (i in 0 until notices.length()) {
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
                .putExtra(PAYLOAD, n.getString("payload"))
            val tap = PendingIntent.getActivity(
                context,
                id,
                open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val silent = n.getBoolean("silent")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, if (silent) QUIET_CHANNEL else MAIL_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).apply {
                    if (!silent) setDefaults(Notification.DEFAULT_ALL)
                }
            }
            // One email: Reply, Archive and Snooze, as on `Notifications`.
            // A notice for several leaves them out, since each would only
            // touch the newest. A Vault notice is about a card, so it has none.
            if (count == 1 && vault == null && away == null && noReply == null) NoticeActions.add(context, builder, id, n.getString("payload"), sender)
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
            try {
                manager.notify(id, builder.build())
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
            val body = context.getString(R.string.notice_sign_in_body)
            val tap = PendingIntent.getActivity(
                context,
                id,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(PAYLOAD, n.getString("payload")),
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

    /** The message a notice was opened for, if it was. */
    fun payload(intent: Intent?): String? = intent?.getStringExtra(PAYLOAD)
}
