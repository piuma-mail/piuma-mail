// Beta and store builds are signed with the project's own key, given by
// tools/android-beta.sh through these variables; without them a release
// build is signed with the local debug key, as before.
// On CI (CI=true) a release build without a key is an error, never a
// quiet debug signature: pull requests use a throwaway key
// (.github/actions/android-throwaway-key), releases the real one.
val releaseKeystore: String? = System.getenv("PIUMA_KEYSTORE_FILE")

// Google signs Android apps in through the reversed client ID as a URL
// scheme: from `google.android=<id>` in PIUMA_OAUTH_CLIENTS, the same
// variable the engine is built with (CONTRIBUTING.md, "Sign-in with
// Microsoft and Google"). Without it the scheme is one nothing opens.
val googleOAuthScheme: String = (System.getenv("PIUMA_OAUTH_CLIENTS") ?: "")
    .split(';', '\n')
    .map { it.trim() }
    .firstOrNull { it.startsWith("google.android=") }
    ?.substringAfter('=')
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?.split('.')
    ?.reversed()
    ?.joinToString(".")
    ?: "mail.piuma.app.google"

// The ABIs this build carries follow `flutter build apk --target-platform`
// (Gradle property "target-platform"; all three when it is not given). The
// Flutter Gradle Plugin always lets all three through, so plugins that ship
// prebuilt libraries for every ABI (CameraX, jni) put lib/x86_64 and
// lib/armeabi-v7a into an arm64-only APK: Android then picks one of those
// ABIs, where libflutter.so and libpiuma_bridge.so are missing, and the app
// crashes at launch. Carrying only the built ABIs makes Android refuse the
// install on any other device instead.
val flutterAbis = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val targetAbis: List<String> =
    ((project.findProperty("target-platform") as String?) ?: flutterAbis.keys.joinToString(","))
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .map { flutterAbis[it] ?: throw GradleException("Unknown target platform: $it") }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "mail.piuma.piuma_mail"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mail.piuma.piuma_mail"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 8: Gemini Nano's library (Model.kt) needs it.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleOAuthScheme"] = googleOAuthScheme
        // With --split-per-abi the splits choose the ABIs instead.
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("piuma") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("PIUMA_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("PIUMA_KEY_ALIAS") ?: "piuma"
                keyPassword = System.getenv("PIUMA_KEY_PASSWORD")
                    ?: System.getenv("PIUMA_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (releaseKeystore != null) "piuma" else "debug"
            )
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Gemini Nano through AICore, for "In short" (Model.kt).
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // A paired Wear OS watch (WatchLink.kt): the Data Layer.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // The AppCompat themes the app lock's BiometricPrompt needs (styles.xml).
    implementation("androidx.appcompat:appcompat:1.7.1")
}

// Checked once the tasks are known, so debug builds and `flutter test`
// keep working without a key.
gradle.taskGraph.whenReady {
    val signsRelease = allTasks.any {
        it.project == project && (it.name == "packageRelease" || it.name == "signReleaseBundle")
    }
    if (signsRelease && releaseKeystore == null) {
        if (System.getenv("CI") != null) {
            throw GradleException(
                "PIUMA_KEYSTORE_FILE is not set: CI never signs a release build with the debug key.",
            )
        }
        logger.warn("PIUMA_KEYSTORE_FILE is not set: this release build is signed with the local debug key.")
    }
}
