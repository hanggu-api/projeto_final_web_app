import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasValidReleaseKeystore: Boolean = run {
    if (!keystorePropertiesFile.exists()) return@run false
    val storeFilePath = keystoreProperties["storeFile"]?.toString()?.trim().orEmpty()
    if (storeFilePath.isEmpty()) return@run false
    rootProject.file(storeFilePath).exists()
}
val isReleaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    val normalized = taskName.lowercase()
    normalized.contains("release") || normalized.contains("bundle")
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.com.play101.serviceapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "br.com.play101.serviceapp"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"

        // Carrega o token do Mapbox para o AndroidManifest
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localProperties.load(FileInputStream(localPropertiesFile))
        }
        val mapboxToken = localProperties.getProperty("mapboxToken") ?: ""
        manifestPlaceholders["mapboxToken"] = mapboxToken
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"]?.toString() ?: ""
                keyPassword = keystoreProperties["keyPassword"]?.toString() ?: ""
                val storeFilePath = keystoreProperties["storeFile"]?.toString()
                if (!storeFilePath.isNullOrEmpty()) {
                    storeFile = rootProject.file(storeFilePath)
                }
                storePassword = keystoreProperties["storePassword"]?.toString() ?: ""
            }
        }
    }

    buildTypes {
        debug {
            if (hasValidReleaseKeystore) {
                // Permite atualizar por cima do app distribuido via Firebase App Distribution
                // sem conflito de assinatura durante testes locais.
                signingConfig = signingConfigs.getByName("release")
            }
        }

        getByName("profile") {
            if (hasValidReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }

        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }

}

dependencies {
    implementation("com.google.android.material:material:1.9.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // Forçar versões compatíveis com AGP 8.7.2
    implementation("androidx.browser:browser:1.8.0")
    implementation("androidx.activity:activity-ktx:1.9.2")
    implementation("androidx.activity:activity:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core:1.13.1")
    androidTestUtil("androidx.test:orchestrator:1.5.1")
}

flutter {
    source = "../.."
}

if (isReleaseBuildRequested && !hasValidReleaseKeystore) {
    throw GradleException(
        "Release keystore ausente ou invalido. Configure android/key.properties com um upload keystore valido antes de gerar bundleRelease."
    )
}
