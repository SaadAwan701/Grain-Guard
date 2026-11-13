import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val releaseKeys = Properties().apply {
    if (signingFile.isFile) signingFile.inputStream().use(::load)
}

android {
    namespace = "pk.grainguard.grainguard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "pk.grainguard.app"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"

        }
        create("production") {
            dimension = "environment"

        }
    }

    signingConfigs {
        if (signingFile.isFile) create("exhibit") {
            storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
        }
    }

    buildTypes {
        release { if (signingFile.isFile) signingConfig = signingConfigs.getByName("exhibit") }
    }
    androidComponents {
        beforeVariants(selector().withBuildType("release")) { variant ->
            if (!signingFile.isFile && variant.productFlavors.any { it.second == "production" }) {
                variant.enable = false
            }
        }
    }
    productFlavors.named("staging") {
        signingConfig = signingConfigs.getByName("debug")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }
