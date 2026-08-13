// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import org.gradle.api.tasks.Exec
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.conatus.crypto"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "dev.conatus.crypto.spike"
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
        buildConfig = false
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("../../../../../../.cache/cryptographic-boundary-jni")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencyLocking {
    lockAllConfigurations()
}

val buildRustArm64 by tasks.registering(Exec::class) {
    val repositoryRoot = rootProject.layout.projectDirectory.dir("../../../../..").asFile
    val nativeCore = rootProject.layout.projectDirectory.dir("../native-core").asFile
    workingDir(repositoryRoot)
    commandLine("./scripts/build-android-crypto-boundary-rust.sh", "arm64-v8a")
    inputs.files(fileTree(nativeCore.resolve("src")), nativeCore.resolve("Cargo.toml"), nativeCore.resolve("Cargo.lock"))
    outputs.file(repositoryRoot.resolve(".cache/cryptographic-boundary-jni/arm64-v8a/libconatus_crypto_boundary_spike.so"))
}

tasks.named("preBuild").configure {
    dependsOn(buildRustArm64)
}
