// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import org.gradle.api.tasks.Exec
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.conatus.terminal"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "dev.conatus.terminal.spike"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.0"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = false
    }

    sourceSets {
        getByName("main") {
            assets.srcDir("../../corpus")
            jniLibs.srcDir("../../../../../../.cache/android-terminal-jni")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.foundation:foundation:1.11.4")
    implementation("androidx.compose.material3:material3:1.4.0")
    implementation("androidx.compose.ui:ui:1.11.4")
    implementation("androidx.compose.ui:ui-tooling-preview:1.11.4")
    debugImplementation("androidx.compose.ui:ui-tooling:1.11.4")
}

dependencyLocking {
    lockAllConfigurations()
}

val buildRustArm64 by tasks.registering(Exec::class) {
    val repositoryRoot = rootProject.layout.projectDirectory.dir("../../../../..").asFile
    val nativeCore = rootProject.layout.projectDirectory.dir("../native-core").asFile
    workingDir(repositoryRoot)
    commandLine("./scripts/build-android-terminal-rust.sh", "arm64-v8a")
    inputs.files(fileTree(nativeCore.resolve("src")), nativeCore.resolve("Cargo.toml"), nativeCore.resolve("Cargo.lock"))
    outputs.file(repositoryRoot.resolve(".cache/android-terminal-jni/arm64-v8a/libconatus_android_terminal_spike.so"))
}

tasks.named("preBuild").configure {
    dependsOn(buildRustArm64)
}
