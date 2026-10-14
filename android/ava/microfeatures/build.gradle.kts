import com.android.build.api.dsl.ApplicationExtension

// Hearth's build of the fork's :microfeatures. Sources are in the submodule.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val avaSrc = rootDir.resolve("third_party/ava/microfeatures/src/main")

// SDK and NDK levels follow the app, which takes them from the Flutter pin.
val app = project(":app").extensions.getByName("android") as ApplicationExtension

android {
    namespace = "com.example.microfeatures"
    compileSdk = app.compileSdk
    ndkVersion = app.ndkVersion

    defaultConfig {
        minSdk = app.defaultConfig.minSdk
        consumerProguardFiles("consumer-rules.pro")
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = avaSrc.resolve("cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets["main"].apply {
        manifest.srcFile(avaSrc.resolve("AndroidManifest.xml"))
        java.srcDir(avaSrc.resolve("java"))
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
