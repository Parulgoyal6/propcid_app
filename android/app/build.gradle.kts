import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystorePropertiesExist = keystorePropertiesFile.exists()

if (keystorePropertiesExist) {
    FileInputStream(keystorePropertiesFile).use {
        keystoreProperties.load(it)
    }
}

// The four fields a real release signing config needs. Checked by name only
// below — never logged, and never used to reconstruct a value in an error
// message.
val requiredSigningKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")

fun missingSigningKeys(): List<String> =
    requiredSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }

fun releaseKeystoreFile(): File? =
    keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }

/**
 * Fails a release build with a clear, secret-free reason — no password, no
 * alias, no filesystem path, never the file's own contents. Debug builds
 * never call this; see the `gradle.taskGraph.whenReady` gate below.
 */
fun failReleaseSigning(reason: String): Nothing {
    throw GradleException(
        "Release signing is not configured ($reason). Release builds never " +
            "fall back to the debug certificate. Create android/key.properties " +
            "(see android/key.properties.example) with storePassword, " +
            "keyPassword, keyAlias and storeFile all set, pointing at a real " +
            "upload keystore, then retry."
    )
}

android {
    namespace = "com.propcid.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.propcid.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Populated whenever `key.properties` has a value for a given key,
        // and left null otherwise — `Properties.getProperty` returns null
        // rather than throwing, so this block is safe to evaluate on every
        // build (including a plain debug `flutter run` with no
        // `key.properties` at all). Nothing here can silently produce a
        // *usable* signing config out of missing data: the
        // `gradle.taskGraph.whenReady` check below is what stops a release
        // build from proceeding when these are incomplete.
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseKeystoreFile()
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Always the real release config, never the debug one. A
            // release artifact must never carry the debug certificate —
            // if the config above is incomplete, the task-graph check
            // below fails the build before this signing config is ever
            // asked to actually sign anything.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Enforced only when a release task is actually going to run: `flutter run`
// and `flutter build apk --debug` invoke `assembleDebug`/`installDebug`,
// whose task graph never contains a "Release" task, so neither ever reaches
// this block or needs `key.properties` to exist.
gradle.taskGraph.whenReady {
    val runningRelease = allTasks.any { it.name.contains("Release") }
    if (!runningRelease) return@whenReady

    if (!keystorePropertiesExist) {
        failReleaseSigning("android/key.properties is missing")
    }

    val missing = missingSigningKeys()
    if (missing.isNotEmpty()) {
        failReleaseSigning("android/key.properties is missing: ${missing.joinToString(", ")}")
    }

    val keystoreFile = releaseKeystoreFile()
    if (keystoreFile == null || !keystoreFile.exists()) {
        failReleaseSigning("the configured keystore file does not exist on disk")
    }
}

// FCM push: the Google services plugin reads google-services.json. It is only
// applied when that file is present, so a checkout without Firebase config
// still builds (PushNotificationService then runs as a no-op).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

flutter {
    source = "../.."
}