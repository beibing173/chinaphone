plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// ─────────────────────────────────────────────────────────────
// 版本号定义处。
// CI 会自动读取 versionName 作为 Release 标签；
// 改版本号 = 发新版。versionCode 必须单调递增。
// ─────────────────────────────────────────────────────────────
val appVersionCode = 1
val appVersionName = "1.0.0"

android {
    namespace = "dev.beibing.chinaphone"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.beibing.chinaphone"
        minSdk = 24
        targetSdk = 34
        versionCode = appVersionCode
        versionName = appVersionName

        // 规则库内置进 APK 资源
        resourceConfigurations += listOf("zh", "en")
    }

    signingConfigs {
        create("release") {
            // CI 用 Secrets 注入；本地没有就用调试签名兜底
            val storePath = System.getenv("SIGNING_KEYSTORE_PATH")
            if (!storePath.isNullOrBlank() && file(storePath).exists()) {
                storeFile = file(storePath)
                storePassword = System.getenv("SIGNING_STORE_PASSWORD")
                keyAlias = System.getenv("SIGNING_KEY_ALIAS")
                keyPassword = System.getenv("SIGNING_KEY_PASSWORD")
            } else {
                storeFile = file("${rootDir}/keystore/chinaphone.jks")
                storePassword = "chinaphone"
                keyAlias = "chinaphone"
                keyPassword = "chinaphone"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // 输出文件名带上版本号，方便 CI 识别
    applicationVariants.all {
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "ChinaPhone-v${appVersionName}.apk"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")

    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
