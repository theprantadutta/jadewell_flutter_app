import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // Crashlytics: uploads the R8 mapping file for release builds.
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// AdMob app id from the gitignored android/ads.properties (written by
// `dart run tool/gen_ad_ids.dart`, docs/ADS.md). Without it the build uses
// Google's sample app id, which serves test ads only.
val adsProperties = Properties().apply {
    val file = rootProject.file("ads.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
// Release signing from the gitignored android/key.properties (storeFile points
// at C:/android-keys/jadewell/upload-keystore.jks; docs/RELEASE_SIGNING.md).
// Without it, release builds fall back to the debug key so `flutter run
// --release` still works locally, and `requireReleaseKey` fails a store build.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile")?.let { file(it).exists() } == true

val admobAppId: String = adsProperties.getProperty("admobAppId")?.takeIf { it.isNotBlank() }
    ?: "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.pranta.jadewell"
    // 37, not flutter.compileSdkVersion (36): the Google Mobile Ads 25.5 / OpenIAP dependency
    // tree pulls androidx.lifecycle 2.11, whose AAR metadata requires compiling against 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pranta.jadewell"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // `-PrequireReleaseKey` (used for store builds) refuses to fall back.
                if (project.hasProperty("requireReleaseKey")) {
                    throw GradleException("android/key.properties is missing or its storeFile doesn't exist (docs/RELEASE_SIGNING.md)")
                }
                signingConfigs.getByName("debug")
            }
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
