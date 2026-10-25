package mail.piuma.piuma_mail

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Option A of `AndroidBackground`: keeps the engine following every
 * account with no app on screen, as on desktop, and shows its notices.
 * Android allows it only with a notice of its own, kept in Silent.
 */
class MailService : Service() {
    @Volatile private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running) return START_STICKY
        running = true
        val accounts = try {
            Background.openEngine(applicationContext)
        } catch (e: Throwable) {
            0
        }
        val notice = ownNotice(accounts)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(OWN_ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(OWN_ID, notice)
        }
        MailNative.start()
        NetworkWatch.follow(applicationContext)
        Thread({
            var looked = 0L
            while (running) {
                val json = MailNative.next(Background.minute(), 60_000)
                if (running) Background.show(applicationContext, json)
                if (running) Background.showSignIn(applicationContext)
                // The Vault's notices: a parcel's day, a bill due soon.
                val now = System.currentTimeMillis()
                if (running && now - looked > 10 * 60_000) {
                    looked = now
                    Background.show(applicationContext, Background.reminders())
                }
            }
        }, "piuma-notices").start()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun ownNotice(accounts: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    getString(R.string.background_channel),
                    NotificationManager.IMPORTANCE_MIN,
                ).apply { setShowBadge(false) },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(getColor(R.color.ic_launcher_background))
            .setContentTitle(resources.getQuantityString(R.plurals.background_title, accounts, accounts))
            .setContentText(getString(R.string.background_detail))
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    companion object {
        private const val OWN_ID = 1
        private const val CHANNEL = "background"

        fun start(context: Context) {
            val intent = Intent(context, MailService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Not allowed from here right now (Android limits starts from
                // the background); the next app start or reboot tries again.
            }
        }
    }
}
