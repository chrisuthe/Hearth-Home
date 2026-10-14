import com.android.build.api.dsl.ApplicationExtension

// Hearth's build of the fork's :satellite. Sources and assets are in the
// submodule; the dependency list mirrors the fork's satellite/build.gradle.kts.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val avaSrc = rootDir.resolve("third_party/ava/satellite/src/main")

// The assets the APK carries, named one by one so a model the fork adds stays
// out until we choose it. hey_luna and the other community models have no
// licence that lets us redistribute them. The wake words must match
// HubConfig.shippedVoiceWakeWords.
val avaAssets = listOf(
    "wakeWords/okay_nabu.json",
    "wakeWords/okay_nabu.tflite",
    "wakeWords/hey_jarvis.json",
    "wakeWords/hey_jarvis.tflite",
    "stopWords/stop.json",
    "stopWords/stop.tflite",
    "sounds/wake_word_triggered.flac",
    "sounds/timer_finished.flac",
    "sounds/error.flac",
    "sounds/LICENSE.md",
)

abstract class StageAvaAssets : Sync() {
    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty
}

val stageAvaAssets = tasks.register<StageAvaAssets>("stageAvaAssets") {
    from(avaSrc.resolve("assets")) { include(avaAssets) }
    into(outputDir)
    // A missing file means the fork moved it; fail rather than ship without it.
    doLast {
        val missing = avaAssets.filterNot { outputDir.get().file(it).asFile.isFile }
        check(missing.isEmpty()) { "Ava assets not found in the submodule: $missing" }
    }
}

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
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(stageAvaAssets, StageAvaAssets::outputDir)
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
