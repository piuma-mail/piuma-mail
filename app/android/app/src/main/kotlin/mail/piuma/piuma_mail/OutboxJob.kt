package mail.piuma.piuma_mail

import android.app.job.JobParameters
import android.app.job.JobService

/**
 * Sends the outbox when a message's time comes (the end of its Undo
 * window, a Send later time), even when the app was swiped away
 * meanwhile and no background service runs. The engine's claims keep a
 * message from going twice beside the app or the service.
 */
class OutboxJob : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        Thread({
            try {
                Background.openEngine(applicationContext)
                MailNative.sendOutbox()
            } catch (e: Throwable) {
                // The app sends it at its next start.
            } finally {
                // A sign-in renewed while sending, even if sending then
                // failed: into the Keystore before the process goes.
                try {
                    Background.keepSecrets(applicationContext)
                } catch (e: Throwable) {
                }
            }
            jobFinished(params, false)
        }, "piuma-outbox").start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}
