plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Firma de release: se usa key.properties solo si esta completo y el keystore existe.
// Si no, el release se firma con la clave de debug para que el proyecto compile en cualquier clon.
val requiredKeystoreKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
val missingKeystoreKeys = requiredKeystoreKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val keystoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { path -> file(path).takeIf { it.exists() } ?: rootProject.file(path).takeIf { it.exists() } }
val hasValidKeystore = keystorePropertiesFile.exists() && missingKeystoreKeys.isEmpty() && keystoreFile != null
if (!hasValidKeystore) {
    val reason = when {
        !keystorePropertiesFile.exists() -> "no se encontro key.properties"
        missingKeystoreKeys.isNotEmpty() -> "key.properties incompleto (faltan: ${missingKeystoreKeys.joinToString()})"
        else -> "el archivo indicado en storeFile no existe"
    }
    logger.warn("WARNING: $reason. El build release se firmara con la clave de DEBUG (no apto para Play Store).")
}

android {
    namespace = "com.smartlook.smartlook_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.smartlook.smartlook_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasValidKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasValidKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}
