pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

rootProject.name = "DosarCuSina"

// Pure Kotlin: the values and engines, no Android.
include(":core")
// Pure Kotlin: the .dosar reader and writer.
include(":archive")
// Pure Kotlin on the JVM: the household database (Room on bundled SQLite).
include(":store")
// The Android app.
include(":app")
