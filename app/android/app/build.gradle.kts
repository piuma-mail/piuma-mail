// Beta and store builds are signed with the project's own key, given by
// tools/android-beta.sh through these variables; without them a release
// build is signed with the local debug key, as before.
val releaseKeystore: String? = System.getenv("PIUMA_KEYSTORE_FILE")

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
}
