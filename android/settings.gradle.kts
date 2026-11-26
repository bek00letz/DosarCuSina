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
// Pure Kotlin: the built-in catalog, read from shared/catalog/.
include(":catalog")
// The Android app.
include(":app")
