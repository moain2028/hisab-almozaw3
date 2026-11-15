import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hisabalmozaw3.distributor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.hisabalmozaw3.distributor"
        // أندرويد 7.0 فما فوق (يغطي أكثر من 97% من الأجهزة)
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // توقيع الإصدار من android/key.properties إن وُجد (لا يُرفع للمستودع)، وإلا مفتاح التطوير
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.isNotEmpty()) {
            create("release") {
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            }
        }
    }

    // التطبيق عربي: نحذف ترجمات مكتبات AndroidX للّغات الأخرى (≈ 150–250 ك.ب)
    androidResources {
        localeFilters += listOf("ar", "en")
    }

    buildTypes {
        release {
            signingConfig = if (keyProps.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // R8: تصغير الكود وحذف غير المستخدم → APK أصغر وأسرع إقلاعاً
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider لفتح ملف التحديث بمثبّت النظام
    implementation("androidx.core:core-ktx:1.13.1")
}
