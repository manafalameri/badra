import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun loadKeyProperties(): Map<String, String> {
    val propsFile = rootProject.file("key.properties")
    if (!propsFile.exists()) return emptyMap()
    val props = Properties()
    propsFile.inputStream().use { stream -> props.load(stream) }
    return props.map { (k, v) -> k.toString() to v.toString() }.toMap()
}

val keyProps = loadKeyProperties()

android {
    namespace = "com.badra.wallet"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.badra.wallet"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Split APKs per ABI so each device only downloads the correct one
    // (dramatically reduces per-ABI APK size and is Play-Stores friendly).
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps["storeFile"]!!)
                storePassword = keyProps["storePassword"]
                keyAlias = keyProps["keyAlias"]
                keyPassword = keyProps["keyPassword"]
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProps.containsKey("storeFile")) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")
    
    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-analytics")

    // freeRASP - Runtime App Self-Protection
    implementation("com.aheaditec.talsec.security:TalsecSecurity-Community-Flutter:13.0.0")
}
