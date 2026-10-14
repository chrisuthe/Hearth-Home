import org.gradle.api.file.SourceDirectorySet

// Hearth's build of the fork's :esphomeproto. Sources are in the submodule.
plugins {
    id("java-library")
    alias(ava.plugins.google.protobuf)
    id("org.jetbrains.kotlin.jvm")
}

val avaSrc = rootDir.resolve("third_party/ava/esphomeproto/src/main")

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
    sourceSets["main"].kotlin.srcDir(avaSrc.resolve("java"))
}

sourceSets["main"].extensions.getByName<SourceDirectorySet>("proto")
    .srcDir(avaSrc.resolve("proto"))

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:${ava.versions.protoc.get()}"
    }
    generateProtoTasks {
        ofSourceSet("main").forEach {
            it.builtins {
                getByName("java") {
                    option("lite")
                }
                create("kotlin") {
                    option("lite")
                }
            }
        }
    }
}

dependencies {
    implementation(ava.kotlinx.coroutines.core)
    implementation(ava.protobuf.java)
    implementation(ava.protobuf.kotlin)
}
