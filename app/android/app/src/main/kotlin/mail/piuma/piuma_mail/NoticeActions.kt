package mail.piuma.piuma_mail

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import java.util.Calendar

/**
 * Reply, Archive and Snooze on a new-mail notice (`Notifications`), done
 * without opening the app: the engine reads the message, then archives,
 * snoozes or answers it, and the notice goes away. Android shows three
 * buttons on a phone, so Delete and Mark read are offered where there is
 * room for them: on a paired watch, with the other three.
 */
class NoticeActions : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(ACTION) ?: return
        // Only a payload this app sealed: the reply's intent is mutable.
        val payload = NoticeSeal.open(context, intent.getStringExtra(PAYLOAD)) ?: return
        val id = intent.getIntExtra(ID, 0)
        // The app lock is on: nothing is done to mail without unlocking.
        // A notice shown before it was turned on loses its buttons; tapped,
        // it opens the app at the lock screen.
        if (AppLockFile.on(context)) {
            Background.blankNotices(context.applicationContext)
            return
        }
        val text = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(REPLY)?.toString().orEmpty()
        if ((action == "reply" || action == "replyAll") && text.isBlank()) return
        val pending = goAsync()
        Thread {
            val done = try {
                Background.openEngine(context.applicationContext)
                MailNative.act(payload, action, tomorrowAtEight(), text)
            } catch (e: Throwable) {
                false
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(id)
            if (!done) failed(context, manager, id)
            WatchLink.publishNow(context.applicationContext)
            pending.finish()
        }.start()
    }

    /** Says so in a notice of its own, opening the app. */
    private fun failed(context: Context, manager: NotificationManager, id: Int) {
        val open = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, "mail_quiet")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(context.getColor(R.color.ic_launcher_background))
            .setContentText(context.getString(R.string.notice_failed))
            .setStyle(Notification.BigTextStyle().bigText(context.getString(R.string.notice_failed)))
            .setContentIntent(open)
            .setAutoCancel(true)
        try {
            manager.notify(id, builder.build())
        } catch (e: SecurityException) {
            // Notifications not allowed: nothing to say it with.
        }
    }

    companion object {
        private const val ACTION = "mail.piuma.notice.action"
        private const val PAYLOAD = "mail.piuma.notice.payload"
        private const val ID = "mail.piuma.notice.id"
        private const val REPLY = "mail.piuma.notice.reply"

        /** Snooze from a notice: tomorrow at 8:00, as swiping left does. */
        fun tomorrowAtEight(): Long {
            val at = Calendar.getInstance()
            at.add(Calendar.DAY_OF_YEAR, 1)
            at.set(Calendar.HOUR_OF_DAY, 8)
            at.set(Calendar.MINUTE, 0)
            at.set(Calendar.SECOND, 0)
            at.set(Calendar.MILLISECOND, 0)
            return at.timeInMillis / 1000
        }

        /**
         * Adds the three buttons to the notice [id] for one email, and on a
         * paired watch Delete and Mark read too, and Reply all when the
         * email went to [others] more people than Reply reaches.
         */
        fun add(context: Context, builder: Notification.Builder, id: Int, payload: String, sender: String, others: Int = 0) {
            fun intent(action: String, code: Int, mutable: Boolean = false): PendingIntent {
                val i = Intent(context, NoticeActions::class.java)
                    .putExtra(ACTION, action)
                    .putExtra(PAYLOAD, NoticeSeal.seal(context, payload))
                    .putExtra(ID, id)
                // RemoteInput fills the reply in, so that one must be mutable.
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
                return PendingIntent.getBroadcast(context, id * 8 + code, i, flags)
            }
            val icon = Icon.createWithResource(context, R.drawable.ic_notification)
            val input = RemoteInput.Builder(REPLY)
                .setLabel(context.getString(R.string.notice_reply_hint, sender))
                .build()
            // What the action means, for watches and cars, from Android 9.
            fun Notification.Action.Builder.means(semantic: Int) = apply {
                if (Build.VERSION.SDK_INT >= 28) setSemanticAction(semantic)
            }
            val reply = Notification.Action.Builder(icon, context.getString(R.string.notice_reply), intent("reply", 1, mutable = true))
                .addRemoteInput(input)
                .means(Notification.Action.SEMANTIC_ACTION_REPLY)
                .setAllowGeneratedReplies(false)
                .build()
            val archive = Notification.Action.Builder(icon, context.getString(R.string.notice_archive), intent("archive", 2))
                .means(Notification.Action.SEMANTIC_ACTION_ARCHIVE)
                .build()
            val snooze = Notification.Action.Builder(icon, context.getString(R.string.notice_snooze), intent("snooze", 3))
                .build()
            val delete = Notification.Action.Builder(icon, context.getString(R.string.notice_delete), intent("delete", 4))
                .means(Notification.Action.SEMANTIC_ACTION_DELETE)
                .build()
            val read = Notification.Action.Builder(icon, context.getString(R.string.notice_read), intent("read", 5))
                .means(Notification.Action.SEMANTIC_ACTION_MARK_AS_READ)
                .build()
            val replyAll = if (others > 0) {
                val everyone = RemoteInput.Builder(REPLY)
                    .setLabel(context.getString(R.string.notice_reply_all_hint, sender, others))
                    .build()
                Notification.Action.Builder(icon, context.getString(R.string.notice_reply_all), intent("replyAll", 6, mutable = true))
                    .addRemoteInput(everyone)
                    .setAllowGeneratedReplies(false)
                    .build()
            } else {
                null
            }
            builder.addAction(reply)
            builder.addAction(archive)
            builder.addAction(snooze)
            // A watch shows what is added here in place of the three.
            builder.extend(
                Notification.WearableExtender()
                    .addAction(reply)
                    .apply { if (replyAll != null) addAction(replyAll) }
                    .addAction(archive)
                    .addAction(read)
                    .addAction(delete)
                    .addAction(snooze),
            )
        }
    }
}
