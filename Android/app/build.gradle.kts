plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val privateCorePack = System.getenv("UNCLEED_PRIVATE_CORES")
val stagedPrivateCores = layout.buildDirectory.dir("private-core-libraries")
val stagePrivateCores = tasks.register<Sync>("stagePrivateCores") {
    privateCorePack?.let { from(it) }
    include("arm64-v8a/*.so", "x86_64/*.so")
    into(stagedPrivateCores)
}
android {
    namespace = "org.uncleed.app"
    compileSdk = 36
    ndkVersion = "27.2.12479018"
    defaultConfig {
        applicationId = "org.uncleed.app"
        minSdk = 28
        targetSdk = 36
        testInstrumentationRunner = "org.uncleed.app.CoreProbeInstrumentation"
        versionCode = 1
        versionName = "0.1.0-dev"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild { cmake { cppFlags += listOf("-std=c++17", "-O2") } }
    }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    buildTypes {
        release { isMinifyEnabled = false; isDebuggable = false }
    }
    sourceSets.getByName("debug") {
        System.getenv("UNCLEED_PRIVATE_RESOURCES")?.let { res.srcDir(it) }
        System.getenv("UNCLEED_PRIVATE_ASSETS")?.let { assets.srcDir(it) }
        privateCorePack?.let { jniLibs.srcDir(stagedPrivateCores) }
    }
    packaging { jniLibs { useLegacyPackaging = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("com.google.android.filament:filament-android:1.66.0")
    implementation("com.google.android.filament:gltfio-android:1.66.0")
    implementation("com.google.android.filament:filament-utils-android:1.66.0")
    testImplementation("junit:junit:4.13.2")
}

tasks.matching { it.name == "preDebugBuild" }.configureEach { dependsOn(stagePrivateCores) }
