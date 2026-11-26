import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.ar.dosarcusina.app"
    // The newest Android APIs, minor release included: Compose asks for 37.1 or later.
    compileSdk {
        version = release(37) { minorApiLevel = 2 }
    }

    defaultConfig {
        // The iPhone app's id, never the first Android version's (docs/DECISIONS.md, 2026-11-25).
        applicationId = "com.ar.dosarcusina.app"
        minSdk = 30
        targetSdk = 37
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // The app writes Romanian on every phone (AppLocale, res/xml/locales_config.xml): only Romanian
    // resources ship, the libraries' other languages left out, and an app bundle never splits by
    // language, so a phone set to another language still gets every resource.
    androidResources {
        localeFilters += "ro"
    }
    bundle {
        language {
            enableSplit = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
            // The tests read the iOS app's answers and the app's own resources from the repository.
            it.systemProperty("dosar.shared", rootDir.resolve("../shared").canonicalPath)
            it.systemProperty("dosar.appMain", file("src/main").canonicalPath)
            it.inputs.dir(rootDir.resolve("../shared/test-vectors/history"))
                .withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("historyVectors")
        }
    }

    lint {
        lintConfig = rootProject.file("lint.xml")
        warningsAsErrors = true
        abortOnError = true
        checkReleaseBuilds = true
        // The modules the app is built from are checked as part of it, with its oldest Android
        // (minSdk): code that runs on the JVM but not on Android 11 fails here.
        checkDependencies = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    implementation(projects.core)
    implementation(projects.archive)
    // The built-in catalog, with shared/catalog/ in its resources.
    implementation(projects.catalog)
    // The household database and the one way it saves; the app opens it with Room's builder for
    // the phone (PhoneDatabases).
    implementation(projects.store)
    implementation(libs.room.runtime)
    implementation(libs.kotlinx.coroutines.core)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

// The unit tests open the binder's store on the JVM, as :store's own tests do: Room and the SQLite
// it bundles built for the machine running them. The phone's builds keep the phone's (the native
// SQLite of the phone's build loads only on Android).
val jvmForUnitTests = setOf(
    "room3-runtime",
    "room3-common",
    "room3-migration",
    "sqlite",
    "sqlite-async",
    "sqlite-bundled",
)
configurations
    .matching { it.name.endsWith("UnitTestRuntimeClasspath") }
    .configureEach {
        resolutionStrategy.eachDependency {
            val multiplatform = requested.group == "androidx.room3" || requested.group == "androidx.sqlite"
            if (multiplatform && requested.name in jvmForUnitTests) {
                useTarget("${requested.group}:${requested.name}-jvm:${requested.version}")
                because("the unit tests run on the JVM, not on a phone")
            }
        }
    }
