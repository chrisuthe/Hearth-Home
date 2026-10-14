import com.android.build.api.dsl.ApplicationExtension

// Hearth's build of SendspinDroid's :shared, the protocol layer. Sources are
// in the submodule; the dependency list mirrors SendspinDroid's
// shared/build.gradle.kts, which has no version catalog to read from.
// expect/actual declarations rule out a plain Android library, so this stays
// Kotlin Multiplatform with only the Android target.
plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val sharedSrc = rootDir.resolve("third_party/sendspindroid/android/shared/src")

// SDK levels follow the app, which takes them from the Flutter pin.
val app = project(":app").extensions.getByName("android") as ApplicationExtension

kotlin {
    androidLibrary {
        namespace = "com.sendspindroid.shared"
        compileSdk = app.compileSdk
        minSdk = app.defaultConfig.minSdk

        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    applyDefaultHierarchyTemplate()

    sourceSets {
        commonMain.get().kotlin.srcDir(sharedSrc.resolve("commonMain/kotlin"))
        // Upstream shares the BouncyCastle crypto between Android and a desktop
        // JVM target through this group. Hearth builds only Android.
        val jvmShared = create("jvmShared") {
            dependsOn(commonMain.get())
            kotlin.srcDir(sharedSrc.resolve("jvmShared/kotlin"))
            dependencies {
                implementation("org.bouncycastle:bcprov-jdk18on:1.80")
            }
        }
        androidMain.get().dependsOn(jvmShared)
        androidMain.get().kotlin.srcDir(sharedSrc.resolve("androidMain/kotlin"))

        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
            implementation("io.ktor:ktor-client-core:3.1.1")
            implementation("io.ktor:ktor-client-websockets:3.1.1")
            // Upstream leaves these out to save about 590 KB: embeddedServer
            // with a lambda never reaches kotlin-reflect, and nothing uses jansi.
            listOf("io.ktor:ktor-server-cio:3.1.1", "io.ktor:ktor-server-websockets:3.1.1").forEach {
                implementation(it) {
                    exclude(group = "org.jetbrains.kotlin", module = "kotlin-reflect")
                    exclude(group = "org.fusesource.jansi", module = "jansi")
                }
            }
        }
        androidMain.dependencies {
            implementation("io.ktor:ktor-client-okhttp:3.1.1")
        }
    }

    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }
}
