// Signed like the phone app (tools/android-beta.sh): Wear OS links a watch
// app with its phone app only when both have the same application id and
// key. Without the variables a release build uses the local debug key.
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
    }

    defaultConfig {
        // The phone app's id: the Data Layer only joins apps that share it.
        applicationId = "mail.piuma.piuma_mail"
        // Wear OS 3, the first with the current Data Layer and tiles.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
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
    // The phone, over the watch's own connection (WatchChannel.kt).
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // The system's voice, keyboard and handwriting input, for Reply.
    implementation("androidx.wear:wear-input:1.2.0")
}
