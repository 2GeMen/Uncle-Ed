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
        versionName = providers.gradleProperty("uncleedVersionName").orElse("0.1.0-dev").get()
        ndk { abiFilters += providers.gradleProperty("uncleedAbis").orElse("arm64-v8a,x86_64").get().split(",") }
        externalNativeBuild { cmake { cppFlags += listOf("-std=c++17", "-O2") } }
    }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    signingConfigs {
        create("beta") {
            System.getenv("UNCLEED_BETA_KEYSTORE")?.let { storeFile = file(it) }
            storePassword = System.getenv("UNCLEED_BETA_STORE_PASSWORD")
            keyAlias = "uncleed-beta"
            keyPassword = System.getenv("UNCLEED_BETA_STORE_PASSWORD")
        }
    }
    buildTypes {
        release { isMinifyEnabled = false; isDebuggable = false }
        create("beta") {
            initWith(getByName("release"))
            applicationIdSuffix = ".beta"
            versionNameSuffix = "-beta.1"
            signingConfig = signingConfigs.getByName("beta")
            matchingFallbacks += listOf("release")
        }
    }
    sourceSets.getByName("debug") {
        System.getenv("UNCLEED_PRIVATE_RESOURCES")?.let { res.srcDir(it) }
        System.getenv("UNCLEED_PRIVATE_ASSETS")?.let { assets.srcDir(it) }
        privateCorePack?.let { jniLibs.srcDir(stagedPrivateCores) }
    }
    // Closed testing only: current appearance is not approved for public distribution.
    sourceSets.getByName("beta") {
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
tasks.matching { it.name == "preBetaBuild" }.configureEach { dependsOn(stagePrivateCores) }
