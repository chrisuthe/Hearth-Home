import com.android.build.api.dsl.ApplicationExtension

// Hearth's build of the fork's :satellite. Sources and assets are in the
// submodule; the dependency list mirrors the fork's satellite/build.gradle.kts.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val avaSrc = rootDir.resolve("third_party/ava/satellite/src/main")

// SDK levels follow the app, which takes them from the Flutter pin.
val app = project(":app").extensions.getByName("android") as ApplicationExtension

android {
    namespace = "com.example.ava.satellite"
    compileSdk = app.compileSdk

    defaultConfig {
        minSdk = app.defaultConfig.minSdk
    }

    sourceSets["main"].apply {
        manifest.srcFile(avaSrc.resolve("AndroidManifest.xml"))
        java.srcDir(avaSrc.resolve("java"))
        assets.srcDir(avaSrc.resolve("assets"))
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        optIn.add("kotlinx.coroutines.ExperimentalCoroutinesApi")
        freeCompilerArgs.add("-Xannotation-default-target=param-property")
    }
}

dependencies {
    api(project(":ava-esphomeproto"))
    api(project(":ava-microfeatures"))
    api(ava.protobuf.kotlin)
    api(ava.androidx.media3.common.ktx)
    implementation(ava.androidx.core.ktx)
    implementation(ava.kotlinx.serialization.json)
    implementation(ava.litert)
    implementation(ava.androidx.media3.exoplayer)
    implementation(ava.androidx.media3.exoplayer.hls)
    implementation(ava.androidx.documentfile)
    implementation(ava.timber)
}
