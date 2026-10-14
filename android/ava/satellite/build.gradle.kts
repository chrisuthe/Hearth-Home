import com.android.build.api.dsl.ApplicationExtension
import javax.inject.Inject

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
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Only assets we hold a licence for reach the APK. Ava also ships hey_luna,
// which has no licence, and models we do not credit. An allowlist, so a fork
// bump that adds a model cannot ship it unnoticed. Credits:
// assets/licenses/notices.json (`microwakeword-models`, `voice-pe-sounds`).
abstract class SatelliteAssets : DefaultTask() {
    @get:InputDirectory
    abstract val source: DirectoryProperty

    @get:OutputDirectory
    abstract val output: DirectoryProperty

    @get:Inject
    abstract val fs: FileSystemOperations

    @TaskAction
    fun copy() {
        fs.sync {
            from(source) {
                include(
                    "sounds/*.flac",
                    "stopWords/stop.json",
                    "stopWords/stop.tflite",
                    "wakeWords/okay_nabu.json",
                    "wakeWords/okay_nabu.tflite",
                    "wakeWords/hey_jarvis.json",
                    "wakeWords/hey_jarvis.tflite",
                )
            }
            into(output)
        }
    }
}

val satelliteAssets = tasks.register<SatelliteAssets>("satelliteAssets") {
    source.set(avaSrc.resolve("assets"))
    output.set(layout.buildDirectory.dir("generated/satelliteAssets"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(
            satelliteAssets, SatelliteAssets::output,
        )
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
