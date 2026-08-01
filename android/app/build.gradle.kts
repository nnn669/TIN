import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.psyche.tin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    val appIdOverride = (findProperty("tinApplicationId") as String?)?.takeIf { it.isNotBlank() }
    val appLabelOverride = (findProperty("tinAppLabel") as String?)?.takeIf { it.isNotBlank() }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = appIdOverride ?: "com.psyche.tin"
        manifestPlaceholders["appLabel"] = appLabelOverride ?: "TIN"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }
    val releaseTaskRequested = gradle.startParameter.taskNames.any {
        it.contains("release", ignoreCase = true)
    }
    if (releaseTaskRequested && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Missing android/key.properties. Release builds must use a configured signing key."
        )
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}