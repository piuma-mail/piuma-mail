package mail.piuma.piuma_mail

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

/**
 * Why the app's process stopped, as Android records it (11 and later), for the next launch to
 * offer a report: stopped responding (ANR), native crashes, and crashes outside Dart. One plain
 * line each: never the trace or the system's description, which can name what was on screen.
 * Each exit is said once; on the first look the history is only marked as seen.
 */
object ExitReasons {
    private const val PREFS = "exit_reasons"
    private const val SEEN = "seen_until"

    fun unseen(context: Context): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val first = !prefs.contains(SEEN)
        val seen = prefs.getLong(SEEN, 0L)
        val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        val exits = try {
            manager.getHistoricalProcessExitReasons(context.packageName, 0, 16)
        } catch (e: Exception) {
            return emptyList()
        }
        var newest = seen
        val out = mutableListOf<String>()
        for (exit in exits) {
            if (exit.timestamp <= seen) continue
            newest = maxOf(newest, exit.timestamp)
            val what = when (exit.reason) {
                ApplicationExitInfo.REASON_ANR -> "the app stopped responding (ANR)"
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash (signal ${exit.status})"
                ApplicationExitInfo.REASON_CRASH -> "crash in Android code (an uncaught exception)"
                ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "the app failed to start"
                else -> null
            } ?: continue
            val where = if (exit.processName == context.packageName) "" else " (background process)"
            val state = when (exit.importance) {
                ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> ", in the foreground"
                else -> ", in the background"
            }
            out.add("Android: $what$where$state")
        }
        prefs.edit().putLong(SEEN, newest).apply()
        return if (first) emptyList() else out
    }
}
