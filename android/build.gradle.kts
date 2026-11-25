import dev.detekt.gradle.extensions.DetektExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.lint) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.detekt) apply false
}

// What the app ships never talks to anyone: no Google Play services, Firebase or ML Kit
// (docs/DECISIONS.md, 2026-11-25). A library that brings one in fails the build.
val forbiddenGroups = listOf(
    "com.google.android.gms",
    "com.google.firebase",
    "com.google.mlkit",
    "com.google.android.play",
    "com.google.android.datatransport",
)

subprojects {
    // detekt on every module, from one configuration: the Android counterpart of
    // scripts/architecture-check.sh grows in config/detekt/detekt.yml.
    apply(plugin = "dev.detekt")
    extensions.configure<DetektExtension> {
        buildUponDefaultConfig.set(true)
        config.setFrom(rootProject.file("config/detekt/detekt.yml"))
    }

    configurations
        .matching { it.name == "runtimeClasspath" || it.name.endsWith("RuntimeClasspath") }
        .configureEach {
            val configurationName = name
            resolutionStrategy.eachDependency {
                val group = requested.group
                if (forbiddenGroups.any { group == it || group.startsWith("$it.") }) {
                    throw GradleException(
                        "$configurationName asks for $group:${requested.name}, which talks to Google. " +
                            "The app takes no SDK that talks to anyone (docs/DECISIONS.md, 2026-11-25).",
                    )
                }
            }
        }

    // The pure Kotlin modules: Java 17 bytecode, warnings as errors, JUnit on the JVM.
    pluginManager.withPlugin("org.jetbrains.kotlin.jvm") {
        extensions.configure<JavaPluginExtension> {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        extensions.configure<KotlinJvmProjectExtension> {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
                allWarningsAsErrors.set(true)
            }
        }
        tasks.withType<Test>().configureEach { useJUnitPlatform() }
        dependencies {
            "testImplementation"(platform(libs.junit.bom))
            "testImplementation"(libs.junit.jupiter)
            "testRuntimeOnly"(libs.junit.platform.launcher)
        }
    }

    // Android Lint on the pure Kotlin modules, with the app's rules (lint.xml).
    pluginManager.withPlugin("com.android.lint") {
        extensions.configure<com.android.build.api.dsl.Lint> {
            lintConfig = rootProject.file("lint.xml")
            warningsAsErrors = true
            abortOnError = true
        }
    }
}
