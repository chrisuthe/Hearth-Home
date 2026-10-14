import com.android.build.api.dsl.ApplicationExtension

// Hearth's build of SendspinDroid's :player: protocol client, sync audio
// output, decoders and the listener for server-initiated connections. Sources
// and R8 rules are in the submodule; the dependency list mirrors SendspinDroid's
// player/build.gradle.kts.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val playerDir = rootDir.resolve("third_party/sendspindroid/android/player")

// SDK levels follow the app, which takes them from the Flutter pin.
val app = project(":app").extensions.getByName("android") as ApplicationExtension

android {
    namespace = "com.sendspindroid.player"
    compileSdk = app.compileSdk

    defaultConfig {
        minSdk = app.defaultConfig.minSdk
        consumerProguardFiles(playerDir.resolve("consumer-rules.pro"))
    }

    sourceSets["main"].apply {
        manifest.srcFile(playerDir.resolve("src/main/AndroidManifest.xml"))
        java.srcDir(playerDir.resolve("src/main/java"))
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

dependencies {
    api(project(":sendspin-shared"))
    api("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
}
