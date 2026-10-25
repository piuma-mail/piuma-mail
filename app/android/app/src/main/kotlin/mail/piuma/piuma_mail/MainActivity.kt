package mail.piuma.piuma_mail

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var notices: MethodChannel? = null
    private var shake: Shake? = null

    /** The notice the app was opened from, until Dart asks for it. */
    private var launchPayload: String? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine reads system settings, such as the DNS servers, through
        // the app context, so it needs it before Flutter starts.
        init(applicationContext)
        NetworkWatch.follow(applicationContext)
        launchPayload = Background.payload(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Background.payload(intent)?.let { notices?.invokeMethod("open", it) }
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
        shake = Shake(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
                    "askBattery" -> {
                        askBattery()
                        result.success(null)
                    }
                    // The name the person gave the phone, for Devices & sync.
                    "deviceName" -> result.success(
                        android.provider.Settings.Global.getString(contentResolver, "device_name")
                            ?: android.os.Build.MODEL
                    )
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
        notices = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mail.piuma/notices")
            .apply {
                setMethodCallHandler { call, result ->
                    if (call.method == "launch") {
                        result.success(launchPayload)
                        launchPayload = null
                    } else {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shake?.stop()
        shake = null
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
        prefs.edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    fun delete(name: String) {
        prefs.edit().remove(name).apply()
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
