plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.kold.f50.monitor.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.kold.f50.monitor.android"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = "17" }

    buildFeatures { buildConfig = true }

    // The web UI is built by Vite into windows/dist and copied into the APK
    // during the Gradle build. No generated dist files belong in git.
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/f50-web"))
}

val webDist = rootProject.file("../windows/dist")
val webAssets = layout.buildDirectory.dir("generated/f50-web")

val npmCommand = if (System.getProperty("os.name").lowercase().contains("win")) "npm.cmd" else "npm"

tasks.register<Exec>("buildWebAssets") {
    workingDir(rootProject.file("../windows"))
    commandLine(npmCommand, "run", "build:android")
}

tasks.register<Copy>("copyWebAssets") {
    dependsOn("buildWebAssets")
    from(webDist)
    into(webAssets)
    doFirst {
        if (!webDist.isDirectory) {
            throw GradleException("windows/dist 未生成，Vite Android 构建失败")
        }
    }
}

tasks.named("preBuild").configure { dependsOn("copyWebAssets") }
