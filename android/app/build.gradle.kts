plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cn.edu.njtc.njtc_schedule"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.edu.njtc.njtc_schedule"
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    androidResources {
        // tessdata/*.traineddata 必须**不压缩**打进 APK：OcrBridge 用
        // `assets.openFd()` 读模型大小（只认未压缩的条目），压缩过的资产会抛
        // 「This file can not be opened as a file descriptor; it is probably compressed」，
        // 结果连 info() 都拿不到（表现为 Dart 侧 MissingPluginException）。见 §9.22。
        noCompress += "traineddata"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 离线 OCR 引擎（Tesseract 4）。语言模型（tessdata/*.traineddata）**不进仓库**，
    // 由 tool/fetch_tessdata.ps1（本地）或 CI 在构建前下载到
    // android/app/src/main/assets/tessdata/，见 .gitignore 与 BUILD_NOTES §9.22。
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}

flutter {
    source = "../.."
}
