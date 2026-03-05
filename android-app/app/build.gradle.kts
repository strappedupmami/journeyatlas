plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.atlasmasa.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.atlasmasa.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
        buildConfigField("int", "LOCAL_QUEUE_MAX_BATCH_BASE", "8")
        buildConfigField("int", "LOCAL_QUEUE_MAX_RUNTIME_MS_BASE", "8000")
        buildConfigField("boolean", "ENABLE_HIGH_PERF_BURST", "true")
        buildConfigField("boolean", "LOCAL_LLM_ENABLED", "true")
        buildConfigField("String", "LOCAL_LLM_ENDPOINT", "\"http://127.0.0.1:8080/v1/chat/completions\"")
        buildConfigField("String", "LOCAL_LLM_MODEL", "\"atlas-local-3b\"")
    }

    flavorDimensions += "audience"
    productFlavors {
        create("yosef") {
            dimension = "audience"
            applicationIdSuffix = ".yosef"
            versionNameSuffix = "-yosef"
            resValue("string", "app_name", "Atlas (Yosef)")
            buildConfigField("int", "LOCAL_QUEUE_MAX_BATCH_BASE", "10")
            buildConfigField("int", "LOCAL_QUEUE_MAX_RUNTIME_MS_BASE", "9500")
        }
        create("yasha") {
            dimension = "audience"
            applicationIdSuffix = ".yasha"
            versionNameSuffix = "-yasha"
            resValue("string", "app_name", "Atlas (Yasha)")
            buildConfigField("int", "LOCAL_QUEUE_MAX_BATCH_BASE", "10")
            buildConfigField("int", "LOCAL_QUEUE_MAX_RUNTIME_MS_BASE", "9500")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
        allWarningsAsErrors = true
        freeCompilerArgs = freeCompilerArgs + listOf("-Xjvm-default=all")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.01.00")

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.navigation:navigation-compose:2.8.5")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3:1.3.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
