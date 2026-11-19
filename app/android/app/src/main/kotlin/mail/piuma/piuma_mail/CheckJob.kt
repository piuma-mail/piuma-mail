package mail.piuma.piuma_mail

import android.app.job.JobParameters
import android.app.job.JobService

/** Option B of `AndroidBackground`: one look at every inbox, every 15 minutes. */
class CheckJob : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        Thread({
            try {
                Background.openEngine(applicationContext)
                Background.show(applicationContext, MailNative.checkOnce(Background.minute()))
                Background.showSignIn(applicationContext)
                Background.show(applicationContext, Background.reminders())
            } catch (e: Throwable) {
                // Next time, then.
            } finally {
                // A sign-in renewed during the look, whatever went wrong after.
                try {
                    Background.keepSecrets(applicationContext)
                } catch (e: Throwable) {
                }
            }
            jobFinished(params, false)
        }, "piuma-check").start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}
