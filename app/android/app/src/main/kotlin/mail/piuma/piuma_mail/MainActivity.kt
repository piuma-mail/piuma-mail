package mail.piuma.piuma_mail

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// A FragmentActivity: the app lock's BiometricPrompt (local_auth) needs one.
class MainActivity : FlutterFragmentActivity() {
    private var notices: MethodChannel? = null
    private var shake: Shake? = null
    private var shared: Shared? = null
    private var clipboard: Clipboard? = null

    /** The notice the app was opened from, until Dart asks for it. */
    private var launchPayload: String? = null

    /**
     * Links, shares and email files, until [Shared] is there: the engine
     * attaches after `onCreate` returns in a FlutterFragmentActivity.
     */
    private val arrivals = Handoff<Intent>()
    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine reads system settings, such as the DNS servers, through
        // the app context, so it needs it before Flutter starts.
        init(applicationContext)
        NetworkWatch.follow(applicationContext)
        launchPayload = Background.payload(applicationContext, intent)
        oauthRedirect(intent)
        super.onCreate(savedInstanceState)
        // Before the first frame: with the app lock on, Piuma stays out of
        // the recent apps' thumbnails and screenshots.
        secure(AppLockFile.on(applicationContext))
        // A link or a share that started the app; not again when Android
        // brings the activity back after it was gone. Held until the engine
        // is configured, which may be after this returns.
        if (savedInstanceState == null) arrivals.offer(intent)
    }

    private fun secure(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Background.payload(applicationContext, intent)?.let { notices?.invokeMethod("open", it) }
        oauthRedirect(intent)
        arrivals.offer(intent)
    }

    /**
     * The browser coming back from Microsoft's or Google's sign-in page.
     * The engine checks the answer's `state` against the sign-in it
     * started and ignores anything else. Links and files other apps hand
     * Piuma go to [Shared] instead.
     */
    private fun oauthRedirect(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val data = intent.data ?: return
        val scheme = data.scheme ?: return
        if (scheme.equals("mailto", ignoreCase = true) || scheme.equals("content", ignoreCase = true)) return
        MailNative.oauthRedirect(data.toString())
    }

    companion object {
        init {
            System.loadLibrary("piuma_bridge")
        }

        @JvmStatic
        external fun init(context: Context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val passwords = Passwords(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mail.piuma/passwords")
            .setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key")!!
                    when (call.method) {
                        "read" -> result.success(passwords.read(key))
                        "write" -> {
                            passwords.write(key, call.argument<String>("value")!!)
                            result.success(null)
                        }
                        "delete" -> {
                            passwords.delete(key)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("passwords", e.message, null)
                }
            }
        Model(flutterEngine.dartExecutor.binaryMessenger)
        Files(this, flutterEngine.dartExecutor.binaryMessenger)
        clipboard = Clipboard(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        shake = Shake(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        shared = Shared(this, flutterEngine.dartExecutor.binaryMessenger).also { s ->
            arrivals.attach { s.handle(it) }
        }
        val context = applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mail.piuma/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mode" -> result.success(Background.mode(context))
                    "setMode" -> {
                        Background.setMode(context, call.argument<String>("mode")!!)
                        result.success(null)
                    }
                    "apply" -> {
                        Background.apply(context)
                        result.success(null)
                    }
                    "outboxAt" -> {
                        Background.outboxAt(
                            context,
                            call.argument<Number>("id")!!.toLong(),
                            call.argument<Number>("at")!!.toLong(),
                        )
                        result.success(null)
                    }
                    "cancelOutbox" -> {
                        Background.cancelOutbox(context, call.argument<Number>("id")!!.toLong())
                        result.success(null)
                    }
                    "refreshSignInNotices" -> {
                        Background.showSignIn(context)
                        result.success(null)
                    }
                    "askBattery" -> {
                        askBattery()
                        result.success(null)
                    }
                    // The name the person gave the phone, for Devices & sync.
                    "deviceName" -> result.success(
                        android.provider.Settings.Global.getString(contentResolver, "device_name")
                            ?: android.os.Build.MODEL
                    )
                    // Why the app stopped since the last look, for a report.
                    "exits" -> result.success(ExitReasons.unseen(context))
                    // Wi-Fi, mobile or offline, for a report.
                    "network" -> result.success(NetworkWatch.kind(context))
                    // The model and Android version, for a report. Never
                    // the name the person gave the phone.
                    "device" -> result.success(
                        listOf(
                            "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                            "Android ${android.os.Build.VERSION.RELEASE} (${android.os.Build.ID})",
                        )
                    )
                    else -> result.notImplemented()
                }
            }
        // The app lock turned on or off (`lock_platform.dart`).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mail.piuma/lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changed" -> {
                        val on = call.argument<Boolean>("on") == true
                        secure(on)
                        // Turned on: the notices already shown lose their
                        // sender, subject and buttons.
                        if (on) Background.blankNotices(context)
                        // The watch shows the mail again, or stops.
                        WatchLink.publish(context)
                        result.success(null)
                    }
                    // The lock closed: the same, for notices shown since.
                    "locked" -> {
                        Background.blankNotices(context)
                        result.success(null)
                    }
                    // The boot count and the time since boot, sleep
                    // included: a clock the wrong-PIN wait can trust. No
                    // boot count, no clock: a wait from another boot could
                    // otherwise be read on this one's (`systemBootClock`).
                    "clock" -> {
                        val boot = Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, -1)
                        result.success(if (boot < 0) null else listOf(boot, SystemClock.elapsedRealtime()))
                    }
                    else -> result.notImplemented()
                }
            }
        notices = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mail.piuma/notices")
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "launch" -> {
                            result.success(launchPayload)
                            launchPayload = null
                        }
                        // Notices the Flutter plugin shows carry sealed
                        // payloads too (notice_seal.dart).
                        "seal" -> result.success(
                            NoticeSeal.seal(applicationContext, call.arguments as String),
                        )
                        "unseal" -> result.success(
                            NoticeSeal.open(applicationContext, call.arguments as? String),
                        )
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        arrivals.detach()
        shake?.stop()
        shake = null
        shared?.stop()
        shared = null
        clipboard?.stop()
        clipboard = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Asks Android to leave the background service out of battery saving. */
    private fun askBattery() {
        val power = getSystemService(PowerManager::class.java)
        if (power.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        } catch (e: Exception) {
            // Some phones have no such screen; the service runs anyway.
        }
    }
}

/**
 * Account passwords, encrypted with a key that never leaves the Android
 * Keystore. Only the encrypted text is kept in the app's preferences.
 */
internal class Passwords(context: Context) {
    private val prefs = context.getSharedPreferences("passwords", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    fun write(name: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        // Written to disk before this returns, or it throws: the app lock
        // counts a PIN try here before checking it, and a try that only
        // might be kept could be repeated without waiting.
        if (!prefs.edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()) {
            throw java.io.IOException("not kept")
        }
    }

    fun delete(name: String) {
        if (!prefs.edit().remove(name).commit()) throw java.io.IOException("not removed")
    }

    fun read(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV_BYTES))
        val plain = cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
        return String(plain, Charsets.UTF_8)
    }

    companion object {
        const val ALIAS = "piuma-passwords"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
